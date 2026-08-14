import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/cli/cli_config.dart';
import 'core/emulator/game_launch_service.dart';
import 'core/emulator/strategy_registry.dart';
import 'core/platform/platform_info.dart';
import 'core/romm/romm_models.dart';
import 'core/romm/romm_service.dart';
import 'core/save/backup_entry.dart';
import 'core/save/backup_repository.dart';
import 'core/save/backup_service.dart';
import 'core/save/save_sync_service.dart';
import 'core/storage/app_preferences.dart';
import 'core/storage/directory_service.dart';
import 'core/storage/shared_preferences_app_preferences.dart';

/// Headless entry point for Freegosy — browse/search the RomM library and
/// launch a game (with save sync verification) without the UI, so a person
/// or an agent can drive it from a terminal without watching the screen.
/// Runs inside the Flutter engine (needed for
/// path_provider/shared_preferences/flutter_secure_storage/hive plugins) but
/// never calls runApp(); no window is shown. Credentials are read from the
/// same storage the GUI app already populated by logging in — no separate
/// headless login step.
///
/// Usage:
///   freegosy.exe --headless list [--search=TERM] [options]
///   freegosy.exe --headless launch --game-id=ID | --name=TERM [options]
///   freegosy.exe --headless interactive
/// (the --headless flag is consumed by this file's caller; see main.dart)
Future<void> runHeadless(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (args.isNotEmpty && (args.first == '--help' || args.first == '-h')) {
    _printUsage();
    exit(0);
  }

  if (args.isEmpty) {
    await _runInteractive();
    return;
  }

  final command = args.first;
  final rest = args.skip(1).toList();

  switch (command) {
    case 'launch':
      await _runLaunch(rest);
      break;
    case 'list':
      await _runList(rest);
      break;
    case 'interactive':
      await _runInteractive();
      break;
    default:
      stderr.writeln('Unknown command: $command\n');
      _printUsage();
      exit(64);
  }
}

void _printUsage() {
  stdout.writeln('''
Freegosy headless mode — browse, search, and launch games without the UI.

Usage:
  freegosy.exe --headless list [--search=TERM] [--platform=SLUG_OR_ID] [--limit=N] [--json]
  freegosy.exe --headless launch (--game-id=ID | --name=TERM) [options]
  freegosy.exe --headless interactive
  freegosy.exe --headless                 (same as interactive)

list options:
  --search=TERM          Filter by name (server-side search)
  --platform=SLUG_OR_ID    Filter by platform
  --limit=N                Max results (default 25)
  --json                   Emit a JSON array to stdout

launch options:
  --game-id=ID            RomM game ID to launch
  --name=TERM              Launch the best name match instead of an ID (ambiguous matches are listed, nothing launches)
  --emulator=ID             Force a specific emulator (e.g. "retroarch") instead of the configured preference, for this run only
  --core=ID                 Force a specific RetroArch core (e.g. "pcsx_rearmed_libretro") instead of the configured/default core, for this run only
  --timeout=SECONDS        Auto-terminate the emulator after N seconds instead of waiting for exit
                             (no effect for emulators that block until exit internally, e.g. MelonDS —
                             the timeout only applies once a process handle is available)
  --json                   Emit machine-readable JSON to stdout (default: human-readable)

Credentials: reused from the account already configured in the Freegosy app
(server URL, username, and password/API key/token, however you signed in).
Run the app once and log in normally before using headless mode.

Exit codes:
  0  command completed successfully
  1  launch or save sync failed
  2  game/config not found, ambiguous match, or invalid arguments
''');
}

Map<String, String> _parseFlags(List<String> args) {
  final flags = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final eq = arg.indexOf('=');
    if (eq == -1) {
      flags[arg.substring(2)] = 'true';
    } else {
      flags[arg.substring(2, eq)] = arg.substring(eq + 1);
    }
  }
  return flags;
}

/// Bundles the services a headless command needs, built the same way the
/// GUI app's providers wire them (see lib/providers/romm_provider.dart),
/// just without Riverpod.
class _HeadlessSession {
  final AppPreferences prefs;
  final RommService rommService;
  final DirectoryService directoryService;
  final StrategyRegistry strategyRegistry;
  final SaveSyncService saveSyncService;
  final GameLaunchService launchService;
  final Box<List> backupBox;

  _HeadlessSession({
    required this.prefs,
    required this.rommService,
    required this.directoryService,
    required this.strategyRegistry,
    required this.saveSyncService,
    required this.launchService,
    required this.backupBox,
  });

  /// Returns null (after printing/emitting a config error) if the session
  /// can't be built — e.g. no RomM login yet, or storage init failed.
  static Future<_HeadlessSession?> start({required bool asJson}) async {
    Hive.registerAdapter(BackupEntryAdapter());
    if (PlatformInfo.current.isLinux) {
      final dir = await getApplicationSupportDirectory();
      await Hive.initFlutter(dir.path);
    } else {
      await Hive.initFlutter();
    }
    final backupBox = await Hive.openBox<List>('freegosy_backups');

    final sharedPrefs = await SharedPreferences.getInstance();
    final prefs = SharedPreferencesAppPreferences(sharedPrefs);

    final rommConfig = await loadCliRommConfig(prefs);
    if (rommConfig.baseUrl.isEmpty) {
      _emitError('No RomM base URL configured. Run the Freegosy app once to log in.', asJson);
      await backupBox.close();
      return null;
    }

    final directoryService = DirectoryService(prefs);
    await directoryService.initialize();
    if (directoryService.status.hasError) {
      _emitError('Storage initialization failed: ${directoryService.status.message}', asJson);
      await backupBox.close();
      return null;
    }

    final rommService = RommService(rommConfig);
    final strategyRegistry = StrategyRegistry(directoryService, prefs);
    final saveSyncService = SaveSyncService(rommService, directoryService, strategyRegistry, prefs);

    final backupRepository = BackupRepository();
    backupRepository.initBox();
    final backupService = BackupService();

    final launchService = GameLaunchService(
      directoryService: directoryService,
      strategyRegistry: strategyRegistry,
      saveSyncService: saveSyncService,
      backupService: backupService,
      backupRepository: backupRepository,
      prefs: prefs,
      rommService: rommService,
    );

    return _HeadlessSession(
      prefs: prefs,
      rommService: rommService,
      directoryService: directoryService,
      strategyRegistry: strategyRegistry,
      saveSyncService: saveSyncService,
      launchService: launchService,
      backupBox: backupBox,
    );
  }

  Future<void> close() => backupBox.close();
}

void _emitError(String message, bool asJson) => _emitResult(_LaunchReport.configError(message), asJson);

/// Resolves a game by ID (exact) or name (server-side search). For name
/// matches: an exact case-insensitive name match wins outright; otherwise
/// if the search returns exactly one result, that's used; multiple
/// candidates are reported (via [onAmbiguous]) instead of guessing.
Future<Game?> _resolveGame(
  RommService rommService, {
  String? gameId,
  String? name,
  void Function(List<Game> candidates)? onAmbiguous,
}) async {
  if (gameId != null) return rommService.getGame(gameId);
  if (name == null) return null;

  final page = await rommService.getGamesPage(search: name, limit: 25);
  if (page.games.isEmpty) return null;
  final exact = page.games.where((g) => g.name.toLowerCase() == name.toLowerCase());
  if (exact.length == 1) return exact.first;
  if (page.games.length == 1) return page.games.first;
  onAmbiguous?.call(page.games);
  return null;
}

Future<void> _runLaunch(List<String> args) async {
  final flags = _parseFlags(args);
  final gameId = flags['game-id'];
  final name = flags['name'];
  final asJson = flags['json'] == 'true';
  final timeoutSeconds = flags['timeout'] != null ? int.tryParse(flags['timeout']!) : null;
  final emulatorOverride = flags['emulator'];
  final coreOverride = flags['core'];

  if (gameId == null && name == null) {
    stderr.writeln('Error: --game-id or --name is required\n');
    _printUsage();
    exit(2);
  }

  final session = await _HeadlessSession.start(asJson: asJson);
  if (session == null) exit(2);

  List<Game>? ambiguous;
  final game = await _resolveGame(session.rommService, gameId: gameId, name: name, onAmbiguous: (c) => ambiguous = c);
  if (game == null) {
    if (ambiguous != null) {
      final list = ambiguous!.map((g) => '  ${g.id}  ${g.name} (${g.platformDisplayName ?? g.platformSlug ?? ''})').join('\n');
      _emitResult(
        _LaunchReport.configError('Multiple games match "$name" — use --game-id instead:\n$list'),
        asJson,
      );
    } else {
      _emitResult(_LaunchReport.configError('Game not found: ${gameId ?? name}'), asJson);
    }
    await session.close();
    exit(2);
  }

  await _launchGame(session, game, timeoutSeconds: timeoutSeconds, asJson: asJson, emulatorOverride: emulatorOverride, coreOverride: coreOverride);
}

/// Shared by both `launch` and `interactive` — launches [game] via the
/// resolved strategy, waits for exit (or the timeout), reports the result,
/// and calls exit() with the appropriate code (unless [returnResult] is set,
/// in which case it returns the report for the caller to render itself).
Future<_LaunchReport> _launchGame(
  _HeadlessSession session,
  Game game, {
  int? timeoutSeconds,
  required bool asJson,
  bool returnResult = false,
  String? emulatorOverride,
  String? coreOverride,
}) async {
  final strategy = emulatorOverride != null
      ? session.strategyRegistry.getStrategyById(emulatorOverride)
      : session.strategyRegistry.getStrategyForSlug(game.platformSlug ?? '', gameId: game.id);
  if (strategy == null) {
    final report = _LaunchReport.configError('No emulator configured for platform "${game.platformSlug}"');
    if (!returnResult) {
      _emitResult(report, asJson);
      await session.close();
      exit(2);
    }
    return report;
  }

  final overrideCoreId = coreOverride ?? session.strategyRegistry.getGameCorePreference(game.id);

  final existingRomPath = await session.directoryService.findExistingRomPath(game);
  if (existingRomPath == null) {
    final report = _LaunchReport.configError('ROM not found on disk for "${game.name}". Download it first via the app.');
    if (!returnResult) {
      _emitResult(report, asJson);
      await session.close();
      exit(2);
    }
    return report;
  }

  final romPath = await session.launchService.resolveRomFileInDirectory(existingRomPath, game.platformSlug);

  stderr.writeln('[freegosy-headless] Launching "${game.name}" via ${strategy.name} ($romPath)...');

  // Most EmulatorStrategy.launchWithHandle implementations (the base class,
  // and every override except RetroArch's) await the process's exitCode
  // internally before returning — e.g. MelonDS does this deliberately, to
  // run SAV<->SRM save translation the moment the emulator closes. That
  // means launchService.launch() itself can block for the entire play
  // session, well before the CLI ever gets a Process handle to arm a kill
  // timer against. So --timeout has to race the whole launch+exit call,
  // not just a post-launch wait, and fall back to killing by executable
  // path (found ahead of time) since no Process handle exists yet.
  Timer? watchdogTimer;
  bool timedOut = false;
  if (timeoutSeconds != null) {
    stderr.writeln('[freegosy-headless] Waiting up to ${timeoutSeconds}s for exit, then terminating...');
    final exePath = await strategy.findExecutable();
    watchdogTimer = Timer(Duration(seconds: timeoutSeconds), () async {
      timedOut = true;
      if (exePath != null) {
        final exeName = Uri.file(exePath).pathSegments.last;
        await Process.run('taskkill', ['/IM', exeName, '/F']);
      }
    });
  } else {
    stderr.writeln('[freegosy-headless] Waiting for game/emulator to exit...');
  }

  try {
    final launched = await session.launchService.launch(game, romPath, strategy, overrideCoreId: overrideCoreId);

    if (launched.process == null) {
      // Fire-and-forget launch path — no process handle, no exit detection possible.
      watchdogTimer?.cancel();
      final report = _LaunchReport.launchedNoHandle(game.id, game.name, strategy.emulatorId, romPath);
      _emitResult(report, asJson);
      if (!returnResult) {
        await session.close();
        exit(0);
      }
      return report;
    }

    // If launch() already blocked until exit (the common case), this
    // resolves immediately. If it returned a live handle (e.g. RetroArch),
    // arm a direct kill against the real Process now that we have one —
    // more reliable than the watchdog's taskkill-by-name fallback.
    if (timeoutSeconds != null && !timedOut) {
      watchdogTimer?.cancel();
      watchdogTimer = Timer(Duration(seconds: timeoutSeconds), () {
        timedOut = true;
        // sigterm (kill()'s default) can be caught/ignored by GUI emulators
        // (Qt/GLFW apps often intercept it for a "save before quit?"
        // prompt); sigkill forces immediate termination.
        launched.process!.kill(ProcessSignal.sigkill);
      });
    }

    final result = await session.launchService.awaitExitAndSync(launched, game, romPath, syncMode: 'both', overrideCoreId: overrideCoreId);
    watchdogTimer?.cancel();

    final report = _LaunchReport(
      ok: result?.syncOk ?? false,
      gameId: game.id,
      gameName: game.name,
      emulatorId: strategy.emulatorId,
      romPath: romPath,
      processExited: true,
      timedOut: timedOut,
      syncTriggered: result != null,
      syncOk: result?.syncOk ?? false,
      backupZipPath: result?.backupZipPath,
      playSessionRecorded: result?.playSessionRecorded ?? false,
      error: null,
    );
    _emitResult(report, asJson);
    if (!returnResult) {
      await session.close();
      exit(report.ok ? 0 : 1);
    }
    return report;
  } catch (e) {
    final report = _LaunchReport.launchError(game.id, game.name, e.toString());
    _emitResult(report, asJson);
    if (!returnResult) {
      await session.close();
      exit(1);
    }
    return report;
  }
}

Future<void> _runList(List<String> args) async {
  final flags = _parseFlags(args);
  final asJson = flags['json'] == 'true';
  final limit = int.tryParse(flags['limit'] ?? '') ?? 25;

  final session = await _HeadlessSession.start(asJson: asJson);
  if (session == null) exit(2);

  try {
    final page = await session.rommService.getGamesPage(
      search: flags['search'],
      platformId: flags['platform'],
      limit: limit,
    );
    _printGameList(page.games, page.total, asJson);
    await session.close();
    exit(0);
  } catch (e) {
    stderr.writeln('Error: failed to list games: $e');
    await session.close();
    exit(1);
  }
}

void _printGameList(List<Game> games, int total, bool asJson) {
  if (asJson) {
    stdout.writeln(jsonEncode({
      'total': total,
      'games': games
          .map((g) => {'id': g.id, 'name': g.name, 'platform': g.platformDisplayName ?? g.platformSlug})
          .toList(),
    }));
    return;
  }
  if (games.isEmpty) {
    stdout.writeln('No games found.');
    return;
  }
  for (final g in games) {
    stdout.writeln('${g.id}\t${g.name}\t${g.platformDisplayName ?? g.platformSlug ?? ''}');
  }
  if (total > games.length) {
    stdout.writeln('... and ${total - games.length} more (use --search to narrow, or --limit to see more)');
  }
}

/// Interactive REPL: search/list games, pick one by number or ID, launch it,
/// repeat. Exits on `q`/`quit`/EOF (Ctrl+D / Ctrl+Z).
Future<void> _runInteractive() async {
  stdout.writeln('Freegosy headless — interactive mode. Type a search term, a game ID, or "q" to quit.\n');

  final session = await _HeadlessSession.start(asJson: false);
  if (session == null) exit(2);

  List<Game> lastResults = [];

  while (true) {
    stdout.write('> ');
    final line = stdin.readLineSync();
    if (line == null || line.trim().toLowerCase() == 'q' || line.trim().toLowerCase() == 'quit') break;
    final input = line.trim();
    if (input.isEmpty) continue;

    // A bare number selects from the last search results; otherwise treat
    // the input as a game ID if it looks numeric-ish and matches nothing
    // in the last results, or as a search term.
    final asIndex = int.tryParse(input);
    if (asIndex != null && asIndex >= 1 && asIndex <= lastResults.length) {
      await _launchGame(session, lastResults[asIndex - 1], asJson: false, returnResult: true);
      continue;
    }

    try {
      final page = await session.rommService.getGamesPage(search: input, limit: 20);
      if (page.games.isEmpty) {
        // Fall back to treating the input as a direct game ID.
        final game = await session.rommService.getGame(input);
        if (game != null) {
          await _launchGame(session, game, asJson: false, returnResult: true);
        } else {
          stdout.writeln('No matches for "$input".');
        }
        continue;
      }
      if (page.games.length == 1) {
        stdout.writeln('One match — launching "${page.games.first.name}"...');
        await _launchGame(session, page.games.first, asJson: false, returnResult: true);
        continue;
      }
      lastResults = page.games;
      stdout.writeln('${page.games.length} matches (of ${page.total}) — enter a number to launch:');
      for (var i = 0; i < page.games.length; i++) {
        final g = page.games[i];
        stdout.writeln('  ${i + 1}. ${g.name} (${g.platformDisplayName ?? g.platformSlug ?? ''})');
      }
    } catch (e) {
      stdout.writeln('Error: $e');
    }
  }

  await session.close();
  exit(0);
}

class _LaunchReport {
  final bool ok;
  final String? gameId;
  final String? gameName;
  final String? emulatorId;
  final String? romPath;
  final bool processExited;
  final bool timedOut;
  final bool syncTriggered;
  final bool syncOk;
  final String? backupZipPath;
  final bool playSessionRecorded;
  final String? error;

  const _LaunchReport({
    required this.ok,
    this.gameId,
    this.gameName,
    this.emulatorId,
    this.romPath,
    this.processExited = false,
    this.timedOut = false,
    this.syncTriggered = false,
    this.syncOk = false,
    this.backupZipPath,
    this.playSessionRecorded = false,
    this.error,
  });

  factory _LaunchReport.configError(String message) => _LaunchReport(ok: false, error: message);

  factory _LaunchReport.launchError(String gameId, String gameName, String message) =>
      _LaunchReport(ok: false, gameId: gameId, gameName: gameName, error: message);

  factory _LaunchReport.launchedNoHandle(String gameId, String gameName, String emulatorId, String romPath) => _LaunchReport(
        ok: true,
        gameId: gameId,
        gameName: gameName,
        emulatorId: emulatorId,
        romPath: romPath,
        processExited: false,
        syncTriggered: false,
        error: 'Launched via fire-and-forget path (no process handle) — exit detection and save sync were not performed.',
      );

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'gameId': gameId,
        'gameName': gameName,
        'emulatorId': emulatorId,
        'romPath': romPath,
        'processExited': processExited,
        'timedOut': timedOut,
        'syncTriggered': syncTriggered,
        'syncOk': syncOk,
        'backupZipPath': backupZipPath,
        'playSessionRecorded': playSessionRecorded,
        'error': error,
      };
}

void _emitResult(_LaunchReport report, bool asJson) {
  if (asJson) {
    stdout.writeln(jsonEncode(report.toJson()));
    return;
  }
  final buf = StringBuffer();
  buf.writeln(report.ok ? 'PASS' : 'FAIL');
  if (report.gameName != null) buf.writeln('  game: ${report.gameName} (${report.gameId})');
  if (report.emulatorId != null) buf.writeln('  emulator: ${report.emulatorId}');
  if (report.romPath != null) buf.writeln('  rom: ${report.romPath}');
  buf.writeln('  processExited: ${report.processExited}');
  if (report.timedOut) buf.writeln('  timedOut: true');
  buf.writeln('  syncTriggered: ${report.syncTriggered}');
  buf.writeln('  syncOk: ${report.syncOk}');
  if (report.backupZipPath != null) buf.writeln('  backup: ${report.backupZipPath}');
  buf.writeln('  playSessionRecorded: ${report.playSessionRecorded}');
  if (report.error != null) buf.writeln('  error: ${report.error}');
  stdout.write(buf.toString());
}
