import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/windows/windows_game_service.dart';
import 'package:freegosy/core/windows/wine_launcher.dart';
import 'package:freegosy/core/storage/app_preferences.dart';

class WindowsStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;
  final AppPreferences _prefs;

  // Manual exe overrides per game id
  final Map<String, String> _exeOverrides = {};
  // Launch arguments per game id
  final Map<String, List<String>> _launchArgsOverrides = {};

  WindowsStrategy(this._directoryService, this._prefs, {super.platform});

  /// Which runner starts Windows games on Linux: `auto` (umu-run/Proton, then wine), `umu` or `wine`.
  static const runnerPrefKey = 'windows_linux_runner';

  /// Per-process overrides for one headless run (`launch --runner= --proton=`); the app never sets them.
  /// [protonOverride] is `auto`, `installed` (never download), a Proton folder, or a name umu downloads
  /// (`GE-Proton`, `UMU-Proton`).
  String? runnerOverride;
  String? protonOverride;

  String? _protonFor(String? installed) {
    switch (protonOverride) {
      case null:
      case 'auto':
        return installed;
      case 'installed':
        return installed ?? (throw Exception('No installed Proton found (looked in Steam\'s compatibilitytools.d and steamapps/common).'));
      default:
        return protonOverride;
    }
  }

  /// The Wine/Proton command for [exePath], and the prefix it uses; null command when no runner is installed.
  ({WineCommand? command, String prefix}) planWine(Game game, String prefixBase, String exePath, List<String> args) {
    final prefix = p.join(prefixBase, 'prefixes', game.id);
    final command = WineLauncher.build(
      exePath: exePath,
      args: args,
      prefixDir: prefix,
      preference: runnerOverride ?? _prefs.getString(runnerPrefKey) ?? 'auto',
      protonPath: _protonFor(WineLauncher.findInstalledProton()),
    );
    return (command: command, prefix: prefix);
  }

  @override
  Future<String?> describeLaunch(Game game, String romPath) async {
    final exePath = _resolveExePath(game, romPath);
    if (exePath == null) return 'No executable found in $romPath (set one with the app\'s game settings).';
    final args = getLaunchArgs(game.id);
    if (!(platform.isLinux && WineLauncher.needsWine(exePath))) {
      return 'Runs directly: ${[exePath, ...args].join(' ')}\nWorking directory: ${File(exePath).parent.path}';
    }
    final base = await _directoryService.getEmulatorAppSupportDirectory('proton');
    final plan = planWine(game, base, exePath, args);
    final c = plan.command;
    if (c == null) return 'No Wine runner found: neither umu-run nor wine is installed.';
    final env = c.environment.entries.map((e) => '${e.key}=${e.value}').join('\n  ');
    return 'Runner: ${c.runner}\nCommand: ${[c.executable, ...c.args].join(' ')}\nWorking directory: ${File(exePath).parent.path}\nEnvironment:\n  $env';
  }

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'Windows';

  @override
  String get emulatorId => 'windows_native';

  @override
  List<String> get supportedSlugs => ['windows', 'pc', 'win'];

  @override
  String get windowsExecutable => '';

  @override
  String get linuxExecutable => '';

  @override
  bool get supportsSaveSync => true;

  static const String _prefsPrefix = 'win_exe_';
  static const String _argsPrefix = 'win_args_';

  void loadPersistedOverrides() {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefsPrefix));
    for (final key in keys) {
      final gameId = key.substring(_prefsPrefix.length);
      final path = _prefs.getString(key);
      if (path != null && path.isNotEmpty) _exeOverrides[gameId] = path;
    }
    final argsKeys = _prefs.getKeys().where((k) => k.startsWith(_argsPrefix));
    for (final key in argsKeys) {
      final gameId = key.substring(_argsPrefix.length);
      final argsStr = _prefs.getString(key);
      if (argsStr != null && argsStr.isNotEmpty) {
        _launchArgsOverrides[gameId] = argsStr.split('\n');
      }
    }
  }

  Future<void> setExeOverride(String gameId, String exePath) async {
    _exeOverrides[gameId] = exePath;
    await _prefs.setString('$_prefsPrefix$gameId', exePath);
  }

  String? getExeOverride(String gameId) => _exeOverrides[gameId];

  Future<void> setLaunchArgs(String gameId, List<String> args) async {
    _launchArgsOverrides[gameId] = args;
    await _prefs.setString('$_argsPrefix$gameId', args.join('\n'));
  }

  List<String> getLaunchArgs(String gameId) =>
      _launchArgsOverrides[gameId] ?? [];

  @override
  Future<void> launch(Game game, String romPath) async {
    // romPath for Windows games is the extracted game folder
    String? exePath = _resolveExePath(game, romPath);

    if (exePath == null) {
      throw Exception(
        'No executable found for ${game.name}. '
        'Please set the exe path manually.',
      );
    }

    final args = getLaunchArgs(game.id);
    final process = await _start(game, exePath, args, ProcessStartMode.normal);

    // Wait up to 5 seconds — if process exits that fast it crashed
    final exitCode = await process.exitCode
        .timeout(const Duration(seconds: 5))
        .catchError((_) => -99999); // timeout = still running = fine

    if (exitCode != -99999 && exitCode != 0) {
      throw Exception(
        '${game.name} crashed immediately (exit code $exitCode). '
        'This is likely due to missing DirectX, Visual C++ redistributables, or other dependencies.',
      );
    }
  }


  /// Starts [exePath]: directly on Windows, through Proton/Wine on Linux (a `.exe` can't run natively there).
  Future<Process> _start(Game game, String exePath, List<String> args, ProcessStartMode mode) async {
    final workingDirectory = File(exePath).parent.path;
    if (platform.isLinux && WineLauncher.needsWine(exePath)) {
      final base = await _directoryService.getEmulatorAppSupportDirectory('proton');
      final plan = planWine(game, base, exePath, args);
      await Directory(plan.prefix).create(recursive: true);
      final command = plan.command;
      if (command == null) {
        throw Exception(
          'Running ${game.name} on Linux needs umu-launcher (umu-run, uses Proton) or Wine. '
          'Install one of them (for example `sudo dnf install umu-launcher` or `sudo apt install wine`).',
        );
      }
      return Process.start(
        command.executable,
        command.args,
        mode: mode,
        workingDirectory: workingDirectory,
        environment: command.environment,
      );
    }
    return Process.start(exePath, args, mode: mode, workingDirectory: workingDirectory);
  }

  /// Resolves the executable path for a Windows game.
  /// Checks user override first, then auto-detects from the game folder.
  String? _resolveExePath(Game game, String romPath) {
    // Check user-set override
    String? exePath = _exeOverrides[game.id];
    if (exePath != null && exePath.isNotEmpty && File(exePath).existsSync()) {
      return exePath;
    }

    // Auto-detect exe in the game folder
    final isDir = Directory(romPath).existsSync();
    final searchDir = isDir ? romPath : File(romPath).parent.path;
    // Use synchronous check for the executable
    return _findExeSync(searchDir, game.name);
  }

  /// Synchronous exe finder for use in launchWithHandle.
  String? _findExeSync(String gameDir, String? hint) {
    final dir = Directory(gameDir);
    if (!dir.existsSync()) return null;

    final exeFiles = <File>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        final ext = entity.path.toLowerCase();
        if (WindowsGameService.launchableExtensions.any((e) => ext.endsWith(e))) {
          final basename = p.basename(entity.path);
          if (basename.startsWith('._')) continue;
          final relPath = entity.path.substring(gameDir.length).toLowerCase();
          if (relPath.contains('__macosx') || relPath.contains('_commonredist')) continue;
          final name = basename.toLowerCase();
          if (WindowsGameService.shouldSkipExe(name)) continue;
          exeFiles.add(entity);
        }
      }
    }

    if (exeFiles.isEmpty) return null;

    // Hint match
    if (hint != null) {
      final hintTokens = _tokenize(hint);
      int bestScore = 0;
      File? bestMatch;
      for (final exe in exeFiles) {
        final exeTokens = _tokenize(p.basenameWithoutExtension(exe.path));
        int score = 0;
        for (final token in hintTokens) {
          if (exeTokens.any((t) => t.contains(token) || token.contains(t))) score++;
        }
        if (score > bestScore) {
          bestScore = score;
          bestMatch = exe;
        }
      }
      if (bestMatch != null && bestScore > 0) return bestMatch.path;
    }

    // Largest exe fallback
    final exes = exeFiles.where((f) => f.path.toLowerCase().endsWith('.exe')).toList();
    final candidates = exes.isNotEmpty ? exes : exeFiles;
    File? largest;
    int largestSize = 0;
    for (final exe in candidates) {
      final size = exe.lengthSync();
      if (size > largestSize) {
        largestSize = size;
        largest = exe;
      }
    }
    return largest?.path;
  }

  static Set<String> _tokenize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2)
        .toSet();
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    // romPath for Windows games is the extracted game folder — unlike a
    // real emulator, a native .exe doesn't take that as a CLI argument, so
    // this must NOT go through DirectoryService.launchGameWithHandle
    // (which appends romPath after args for every emulator strategy). Doing
    // so broke executables that take their own complete argument list, e.g.
    // OpenGOAL's shared "gk.exe --game jak1" launcher (issue #47) — the
    // game folder path was tacked on as an unexpected trailing argument.
    String? exePath = _resolveExePath(game, romPath);

    if (exePath == null) {
      throw Exception(
        'No executable found for ${game.name}. '
        'Please set the exe path manually.',
      );
    }

    final args = getLaunchArgs(game.id);
    final process = await _start(game, exePath, args, ProcessStartMode.normal);
    // Drain stdout/stderr to avoid pipe-buffer deadlock — same reasoning as
    // DirectoryService.launchGameWithHandle's drain() calls.
    process.stdout.drain();
    process.stderr.drain();
    return process;
  }

  @override
  Future<void> launchStandalone() async {}

  @override
  String resolveSavePath(Game game) => '';
}
