part of 'main_cli.dart';

// Headless inspection commands: platforms, emulators, doctor, info, playtime, saves.
// They share main_cli.dart's session and flag helpers (this is a `part`), and every one
// takes --json so scripts and agents can read the result.

String _fmtBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble(), i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
}

/// Where [s] is installed, or null. Windows games have no executable of their own: they run directly on
/// Windows and through umu-run or wine on Linux.
Future<String?> _emulatorLocation(EmulatorStrategy s) async {
  try {
    if (s.emulatorId == 'windows_native') {
      if (!PlatformInfo.current.isLinux) return 'built in';
      return WineLauncher.find('umu-run') ?? WineLauncher.find('wine');
    }
    return await s.findExecutable();
  } catch (_) {
    return null;
  }
}

void _out(Object? json, void Function() text, bool asJson) {
  if (asJson) {
    stdout.writeln(jsonEncode(json));
  } else {
    text();
  }
}

/// A platform id from `--platform=`: a number is taken as the id, anything else is matched
/// against RomM's slug, folder name and display name (case-insensitive). Null (after saying why) when unknown.
Future<String?> _platformIdFromFlag(RommService romm, String? value) async {
  if (value == null || value.isEmpty) return null;
  if (int.tryParse(value) != null) return value;
  final platforms = await romm.getPlatforms();
  final wanted = value.toLowerCase();
  for (final p in platforms) {
    if (p.slug.toLowerCase() == wanted || p.fsSlug.toLowerCase() == wanted || p.displayName.toLowerCase() == wanted || p.name.toLowerCase() == wanted) {
      return p.id.toString();
    }
  }
  final close = platforms.where((p) => p.displayName.toLowerCase().contains(wanted) || p.slug.toLowerCase().contains(wanted)).toList();
  stderr.writeln('Error: unknown platform "$value".${close.isEmpty ? '' : ' Did you mean: ${close.map((p) => p.slug).join(', ')}?'} (see `platforms`)');
  exit(2);
}

Future<void> _runPlatforms(List<String> args) async {
  final flags = _parseFlags(args);
  final asJson = flags['json'] == 'true';
  final session = await _HeadlessSession.start(asJson: asJson);
  if (session == null) exit(2);
  try {
    final platforms = await session.rommService.getPlatforms()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    final rows = [
      for (final p in platforms)
        () {
          final strategy = session.strategyRegistry.getStrategyForSlug(p.slug);
          return {
            'id': p.id,
            'slug': p.slug,
            'name': p.displayName,
            'games': p.gamesCount,
            'firmware': p.firmwareCount,
            'emulator': strategy?.emulatorId,
          };
        }(),
    ];
    _out(rows, () {
      stdout.writeln('ID\tSLUG\tGAMES\tEMULATOR\tNAME');
      for (final r in rows) {
        stdout.writeln('${r['id']}\t${r['slug']}\t${r['games']}\t${r['emulator'] ?? '-'}\t${r['name']}');
      }
    }, asJson);
    await session.close();
    exit(0);
  } catch (e) {
    stderr.writeln('Error: failed to list platforms: $e');
    await session.close();
    exit(1);
  }
}

Future<void> _runEmulators(List<String> args) async {
  final flags = _parseFlags(args);
  final asJson = flags['json'] == 'true';
  final session = await _HeadlessSession.start(asJson: asJson);
  if (session == null) exit(2);
  final rows = <Map<String, Object?>>[];
  for (final s in session.strategyRegistry.allStrategies) {
    final path = await _emulatorLocation(s);
    rows.add({
      'id': s.emulatorId,
      'name': s.name,
      'installed': path != null,
      'path': path,
      'platforms': s.supportedSlugs,
      'saveSync': s.supportsSaveSync,
      'stateSync': s.supportsStateSync,
    });
  }
  _out(rows, () {
    for (final r in rows) {
      stdout.writeln('${(r['installed'] as bool) ? '[installed]' : '[missing]  '} ${r['id']}  (${r['name']})'
          '${(r['path'] != null) ? '\n              ${r['path']}' : ''}'
          '\n              platforms: ${(r['platforms'] as List).join(', ')}${(r['saveSync'] as bool) ? '  | save sync' : ''}${(r['stateSync'] as bool) ? ' | state sync' : ''}');
    }
  }, asJson);
  await session.close();
  exit(0);
}

/// Names a check's result for `doctor`.
class _Check {
  final String area;
  final String level; // ok | info | warn | fail
  final String text;
  _Check(this.area, this.level, this.text);
  Map<String, String> toJson() => {'area': area, 'level': level, 'text': text};
}

Future<void> _runDoctor(List<String> args) async {
  final flags = _parseFlags(args);
  final asJson = flags['json'] == 'true';
  final checks = <_Check>[];
  void add(String area, String level, String text) => checks.add(_Check(area, level, text));

  add('system', 'info', '${PlatformInfo.current.isLinux ? 'Linux' : PlatformInfo.current.isWindows ? 'Windows' : 'macOS'}, Freegosy headless build');

  final session = await _HeadlessSession.start(asJson: asJson);
  if (session == null) exit(2);
  try {
    // RomM
    try {
      final caps = await session.rommService.fetchCapabilities();
      add('romm', 'ok', 'Server ${session.rommService.config.baseUrl}, version ${caps.version}'
          '${caps.hasDeviceSaveSync ? ' (per-device saves and play sessions available)' : ' (older than 4.9: no per-device saves)'}');
      final platforms = await session.rommService.getPlatforms();
      final games = platforms.fold<int>(0, (a, p) => a + p.gamesCount);
      add('romm', 'ok', 'Signed in; ${platforms.length} platforms, $games games');
    } catch (e) {
      add('romm', 'fail', 'Could not read the library: $e');
    }

    // Paths
    final roms = await session.directoryService.getRomsDirectory();
    final romsDir = Directory(roms);
    if (!romsDir.existsSync()) {
      add('paths', 'warn', 'ROMs folder $roms does not exist yet (created on the first download)');
    } else {
      final free = await DiskSpace.freeBytes(roms);
      add('paths', 'ok', 'ROMs folder $roms${free == null ? '' : ', ${_fmtBytes(free)} free'}');
      if (free != null && free < 2 * 1024 * 1024 * 1024) add('paths', 'warn', 'Less than 2 GB free where games download');
    }

    // Emulators
    var installed = 0;
    final missing = <String>[];
    for (final s in session.strategyRegistry.allStrategies) {
      final path = await _emulatorLocation(s);
      if (path != null) {
        installed++;
      } else {
        missing.add(s.emulatorId);
      }
    }
    add('emulators', installed > 0 ? 'ok' : 'warn', '$installed of ${installed + missing.length} emulators found${missing.isEmpty ? '' : ' (missing: ${missing.join(', ')})'}');

    // Linux: Windows games, Flatpak, controllers
    if (PlatformInfo.current.isLinux) {
      for (final name in ['umu-run', 'wine', 'flatpak']) {
        final path = WineLauncher.find(name);
        add('linux', path != null ? 'ok' : (name == 'flatpak' ? 'info' : 'warn'), path != null ? '$name: $path' : '$name: not found');
      }
      final proton = WineLauncher.findInstalledProton();
      add('linux', proton != null ? 'ok' : 'info', proton != null
          ? 'Installed Proton: $proton'
          : 'No Proton installed; umu-run downloads GE-Proton on first use');
      if (WineLauncher.find('umu-run') == null && WineLauncher.find('wine') == null) {
        add('linux', 'warn', 'Windows games cannot start without umu-run or wine');
      }
    }

    // Local data
    final saved = SavedFilterStore(session.prefs).all().length;
    add('data', 'info', 'Saved filter sets: $saved; games with play time: ${PlayTimeStore(session.prefs).allStats().length}');
  } catch (e) {
    add('doctor', 'fail', 'Unexpected error: $e');
  }
  await session.close();

  final problems = checks.where((c) => c.level == 'fail').length;
  final warnings = checks.where((c) => c.level == 'warn').length;
  _out({'ok': problems == 0, 'problems': problems, 'warnings': warnings, 'checks': checks.map((c) => c.toJson()).toList()}, () {
    const marks = {'ok': '[ok]  ', 'info': '[info]', 'warn': '[warn]', 'fail': '[FAIL]'};
    for (final c in checks) {
      stdout.writeln('${marks[c.level]} ${c.area}: ${c.text}');
    }
    stdout.writeln('\n${problems == 0 ? 'No problems' : '$problems problem(s)'}, $warnings warning(s).');
  }, asJson);
  exit(problems == 0 ? 0 : 1);
}

/// Resolves --game-id/--name for the commands below, printing why and exiting 2 when it can't.
Future<Game> _gameFromFlags(_HeadlessSession session, Map<String, String> flags) async {
  final gameId = _nonEmpty(flags['game-id']);
  final name = _nonEmpty(flags['name']);
  if (gameId == null && name == null) {
    stderr.writeln('Error: --game-id or --name is required');
    await session.close();
    exit(2);
  }
  List<Game>? ambiguous;
  final game = await _resolveGame(session.rommService, gameId: gameId, name: name, onAmbiguous: (c) => ambiguous = c);
  if (game == null) {
    if (ambiguous != null) {
      stderr.writeln('Multiple games match "$name" - use --game-id:\n${ambiguous!.map((g) => '  ${g.id}  ${g.name} (${g.platformDisplayName ?? g.platformSlug ?? ''})').join('\n')}');
    } else {
      stderr.writeln('Game not found: ${gameId ?? name}');
    }
    await session.close();
    exit(2);
  }
  return game;
}

Future<void> _runInfo(List<String> args) async {
  final flags = _parseFlags(args);
  final asJson = flags['json'] == 'true';
  final session = await _HeadlessSession.start(asJson: asJson);
  if (session == null) exit(2);
  final game = await _gameFromFlags(session, flags);
  try {
    final existing = await session.directoryService.findExistingRomPath(game);
    final strategy = session.strategyRegistry.getStrategyForSlug(game.platformSlug ?? '', gameId: game.id);
    final play = PlayTimeStore(session.prefs).statsFor(game.id);
    final info = <String, Object?>{
      'id': game.id,
      'name': game.name,
      'platform': game.platformDisplayName ?? game.platformSlug,
      'platformSlug': game.platformSlug,
      'sizeBytes': game.fileSize,
      'files': game.files.length,
      'genres': game.genres,
      'franchises': game.franchises,
      'companies': game.companies,
      'players': game.playerCount,
      'rating': game.averageRating,
      'released': game.firstReleaseDate == null ? null : DateTime.fromMillisecondsSinceEpoch(game.firstReleaseDate!, isUtc: true).toIso8601String().split('T').first,
      'regions': game.regions,
      'languages': game.languages,
      'summary': game.summary,
      'yourRating': game.userRating,
      'status': game.status,
      'lastPlayed': game.lastPlayed?.toIso8601String(),
      'downloaded': existing != null,
      'localPath': existing,
      'emulator': strategy?.emulatorId,
      'emulatorInstalled': strategy == null ? null : await _emulatorLocation(strategy) != null,
      'localPlaySeconds': play?.total.inSeconds,
      'localSessions': play?.sessions,
      'retroAchievementsId': game.raId,
    };
    _out(info, () {
      stdout.writeln('${game.name}  (id ${game.id})');
      stdout.writeln('  Platform:   ${info['platform']} (${info['platformSlug']})');
      stdout.writeln('  Size:       ${_fmtBytes(game.fileSize)}, ${game.files.length} file(s)');
      if (game.genres.isNotEmpty) stdout.writeln('  Genres:     ${game.genres.join(', ')}');
      if (game.franchises.isNotEmpty) stdout.writeln('  Franchises: ${game.franchises.join(', ')}');
      if (game.companies.isNotEmpty) stdout.writeln('  Companies:  ${game.companies.join(', ')}');
      stdout.writeln('  Players:    ${game.playerCount ?? '-'}   Rating: ${game.averageRating?.toStringAsFixed(0) ?? '-'}   Released: ${info['released'] ?? '-'}');
      stdout.writeln('  Yours:      rating ${game.userRating}, status ${game.status ?? '-'}, last played ${game.lastPlayed?.toLocal().toString().split('.').first ?? 'never'}');
      stdout.writeln('  On disk:    ${existing ?? 'not downloaded'}');
      stdout.writeln('  Emulator:   ${strategy == null ? 'none configured' : '${strategy.name}${info['emulatorInstalled'] == true ? '' : ' (not installed)'}'}');
      stdout.writeln('  Play time:  ${play == null ? 'none recorded here' : '${PlayTimeStore.format(play.total)} in ${play.sessions} session(s)'}');
      if (game.summary != null && game.summary!.isNotEmpty) stdout.writeln('\n${game.summary}');
    }, asJson);
    await session.close();
    exit(0);
  } catch (e) {
    stderr.writeln('Error: $e');
    await session.close();
    exit(1);
  }
}

Future<void> _runPlaytime(List<String> args) async {
  final flags = _parseFlags(args);
  final asJson = flags['json'] == 'true';
  final limit = int.tryParse(flags['limit'] ?? '') ?? 15;
  final session = await _HeadlessSession.start(asJson: asJson);
  if (session == null) exit(2);
  final store = PlayTimeStore(session.prefs);
  final ids = mostPlayedGameIds(store, limit: limit);
  final games = await session.rommService.getGamesByIds(ids);
  final rows = [
    for (final g in games)
      {
        'id': g.id,
        'name': g.name,
        'platform': g.platformDisplayName ?? g.platformSlug,
        'seconds': store.statsFor(g.id)?.total.inSeconds ?? 0,
        'sessions': store.statsFor(g.id)?.sessions ?? 0,
        'last': store.statsFor(g.id)?.lastPlayed?.toIso8601String(),
      }
  ];
  _out(rows, () {
    if (rows.isEmpty) stdout.writeln('No play time recorded on this computer yet.');
    for (final r in rows) {
      stdout.writeln('${PlayTimeStore.format(Duration(seconds: r['seconds'] as int)).padRight(16)} ${r['sessions']} session(s)  ${r['name']}  (${r['platform']}, id ${r['id']})');
    }
  }, asJson);
  await session.close();
  exit(0);
}

/// `saves` inspects and drives save sync for one game: `check` (default) reports what is
/// local and on RomM and what looks wrong, `push` uploads, `pull` downloads, `backups` lists local backups.
Future<void> _runSaves(List<String> args) async {
  final flags = _parseFlags(args);
  final asJson = flags['json'] == 'true';
  final action = args.where((a) => !a.startsWith('--')).firstOrNull ?? 'check';
  if (!const ['check', 'push', 'pull', 'backups'].contains(action)) {
    stderr.writeln('Unknown saves action: $action (use check, push, pull, backups)');
    exit(64);
  }
  final session = await _HeadlessSession.start(asJson: asJson);
  if (session == null) exit(2);
  final game = await _gameFromFlags(session, flags);
  final emulatorId = _nonEmpty(flags['emulator']);
  try {
    final existing = await session.directoryService.findExistingRomPath(game);
    if (existing == null) {
      stderr.writeln('"${game.name}" is not downloaded, so there is no local save location to use.');
      await session.close();
      exit(2);
    }
    final romPath = await session.launchService.resolveRomFileInDirectory(existing, game.platformSlug);
    switch (action) {
      case 'check':
        final report = await session.saveSyncService.checkSync(game, romPath, emulatorId: emulatorId);
        _out({
          'game': report.gameName,
          'emulator': report.emulator,
          'saveDir': report.saveDir,
          'local': [for (final s in report.localSaves) {'name': s.name, 'size': s.size, 'modified': s.modified.toIso8601String()}],
          'cloud': report.cloud == null ? null : {'name': report.cloud!.name, 'size': report.cloud!.size, 'updated': report.cloud!.updated?.toIso8601String()},
          'problems': report.hasProblems,
          'warnings': report.hasWarnings,
          'findings': [for (final f in report.findings) {'level': f.level.name, 'text': f.text}],
        }, () => stdout.writeln(report.toText()), asJson);
        await session.close();
        exit(report.hasProblems ? 1 : 0);
      case 'push':
        final ok = await session.saveSyncService.pushSaves(game, romPath, force: flags['force'] == 'true', emulatorId: emulatorId);
        _out({'ok': ok, 'action': 'push', 'game': game.name}, () => stdout.writeln(ok ? 'Saves uploaded.' : 'Nothing was uploaded (no local saves, or nothing newer).'), asJson);
        await session.close();
        exit(ok ? 0 : 1);
      case 'pull':
        final ok = await session.saveSyncService.pullSave(game, romPath, emulatorId: emulatorId);
        _out({'ok': ok, 'action': 'pull', 'game': game.name}, () => stdout.writeln(ok ? 'Saves downloaded.' : 'Nothing was downloaded (no cloud save, or the local one is newer).'), asJson);
        await session.close();
        exit(ok ? 0 : 1);
      default: // backups
        final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'backups'));
        final files = !dir.existsSync()
            ? <File>[]
            : (dir.listSync().whereType<File>().where((f) => p.basename(f.path).startsWith('freegosy_${game.id}_')).toList()
              ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync())));
        _out([for (final f in files) {'path': f.path, 'size': f.lengthSync(), 'modified': f.lastModifiedSync().toIso8601String()}], () {
          if (files.isEmpty) stdout.writeln('No local backups for "${game.name}".');
          for (final f in files) {
            stdout.writeln('${f.lastModifiedSync().toLocal().toString().split('.').first}  ${_fmtBytes(f.lengthSync()).padLeft(8)}  ${f.path}');
          }
        }, asJson);
        await session.close();
        exit(0);
    }
  } catch (e) {
    stderr.writeln('Error: $e');
    await session.close();
    exit(1);
  }
}
