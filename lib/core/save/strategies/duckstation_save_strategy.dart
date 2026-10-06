import 'dart:io';
import 'dart:io' as io;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../disc/serial_extraction_service.dart';
import '../../platform/platform_info.dart';
import '../../romm/game_id_resolver.dart';
import '../../romm/romm_models.dart';
import '../../storage/app_preferences.dart';
import '../../storage/directory_service.dart';
import '../formats/ps1_memory_card.dart';
import '../save_state_info.dart';
import '../save_strategy.dart';
import '../state_sync_capable.dart';
import 'duckstation_config.dart';
import 'duckstation_state_file.dart';

/// Save strategy for DuckStation (PlayStation 1).
/// Memcards: {dataDir}/memcards/*.mcd
/// States:   {dataDir}/savestates/{SERIAL}_{N|resume}.sav — synced separately
///           through [StateSyncCapable] / StateSyncService, not by this
///           strategy's save methods.
class DuckstationSaveStrategy extends SaveStrategy with StateSyncCapable {
  final DirectoryService _directoryService;
  final PlatformInfo _platform;
  final SerialExtractionService _serialExtractionService;
  final ZstdDecompressor? _zstd;

  /// PS1's `SYSTEM.CNF` boot line, e.g. `BOOT = cdrom:\SLES_035.08;1`. The
  /// `\s*=` right after `BOOT` keeps PS2's `BOOT2 =` line from matching.
  static final _bootLinePattern = RegExp(
      r'BOOT\s*=\s*cdrom[^:]*:\\?([A-Z]{4}[_-]\d{3}[.]\d{2})',
      caseSensitive: false);

  DuckstationSaveStrategy(this._directoryService, AppPreferences prefs,
      {PlatformInfo? platform,
      SerialExtractionService? serialExtractionService,
      ZstdDecompressor? zstd})
      : _platform = platform ?? PlatformInfo.current,
        _zstd = zstd,
        _serialExtractionService = serialExtractionService ??
            SerialExtractionService(_directoryService, prefs, platform: platform);

  @override
  String get strategyId => 'duckstation';

  /// The game's PS1 serial (e.g. "SLES-03508"): RomM's, else read from the
  /// ROM (see [SerialExtractionService]). Null if neither has it.
  Future<String?> _serial(Game game, String romPath) => GameIdResolver.resolve(
        label: 'DuckStation ${game.name}',
        server: GameIdResolver.discSerial(game, romPath),
        shape: GameIdResolver.ps1ps2Serial,
        local: () => _serialExtractionService.extractSerial(romPath: romPath, bootLinePattern: _bootLinePattern,
            chdmanCandidates: [(emulatorId: 'duckstation', exeName: _getEmuExe())]),
      );

  /// DuckStation's per-game state naming: `SERIAL_N.sav` or
  /// `SERIAL_resume.sav` (System::GetGameSaveStateFileName). The character
  /// class excludes path separators; `.sav.backup` doesn't match. The global
  /// slots (`savestate_N.sav`) aren't tied to a game and are never matched.
  static final _stateFilePattern = RegExp(r'^([A-Za-z0-9-]+)_(resume|\d{1,2})\.sav$');

  static String _serialKey(String serial) =>
      serial.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static RegExpMatch? _matchState(String fileName) {
    final match = _stateFilePattern.firstMatch(fileName);
    if (match == null || match.group(1)!.toLowerCase() == 'savestate') return null;
    return match;
  }

  @override
  Future<String> stateDirectory(Game game, String romPath) async =>
      p.join(await _getBaseDir(platformSlug: game.platformSlug), 'savestates');

  @override
  Future<bool Function(String fileName)?> stateFileMatcher(
      Game game, String romPath) async {
    final serial = await _serial(game, romPath);
    if (serial == null) return null;
    final wanted = _serialKey(serial);
    return (String fileName) {
      final match = _matchState(fileName);
      return match != null && _serialKey(match.group(1)!) == wanted;
    };
  }

  @override
  bool looksLikeValidState(Uint8List bytes) => DuckstationStateFile.hasMagic(bytes);

  @override
  StateSlot slotOf(String fileName) {
    final match = _matchState(fileName);
    if (match == null) return UnknownStateSlot(fileName);
    final slot = match.group(2)!;
    return slot == 'resume' ? const AutoStateSlot() : NumberedStateSlot(int.parse(slot));
  }

  /// DuckStation records only its state format version, not the build that
  /// wrote the state: there is no emulator version to compare.
  @override
  Future<StateFileInfo> describeState(File file) async {
    final base = await super.describeState(file);
    final format = await DuckstationStateFile.readFormatVersion(file);
    return StateFileInfo(savedAt: base.savedAt, formatId: format?.toString());
  }

  @override
  Future<Uint8List?> stateScreenshot(File file) =>
      DuckstationStateFile.readScreenshot(file, zstd: _zstd);

  String _getEmuExe() {
    if (_platform.isWindows) return 'duckstation-qt-x64-ReleaseLTCG.exe';
    if (_platform.isMacOS) return 'DuckStation.app/Contents/MacOS/DuckStation';
    return 'duckstation-qt';
  }

  Future<String> _getBaseDir({String? platformSlug}) async {
    // 1. Check portable mode first (all platforms)
    //
    // DuckStation treats the install as portable when EITHER portable.txt OR
    // settings.ini exists next to the executable (upstream core.cpp):
    //   if (FileExists("portable.txt") || FileExists("settings.ini"))
    //     DataRoot = exe dir
    // Scoop installs and some portable builds only have settings.ini (created
    // on first run), so we must check both or we fall through to the wrong
    // directory and report "no saves" (issue #28).
    final exePath = await _directoryService.findEmulatorExecutable(
        'duckstation', _getEmuExe());
    if (exePath != null) {
      String emulatorDir = File(exePath).parent.path;
      if (_platform.isMacOS && exePath.contains('.app/Contents/MacOS/')) {
        emulatorDir = io.File(exePath).parent.parent.parent.parent.path;
      }
      final portableMarker = File(p.join(emulatorDir, 'portable.txt'));
      final settingsMarker = File(p.join(emulatorDir, 'settings.ini'));
      if (await portableMarker.exists() || await settingsMarker.exists()) {
        debugPrint('[DuckStation] portable mode detected via '
            '${await portableMarker.exists() ? "portable.txt" : "settings.ini"} → $emulatorDir');
        return emulatorDir;
      }
      debugPrint('[DuckStation] exe found at $exePath but no portable.txt/settings.ini — not portable');
    } else {
      debugPrint('[DuckStation] no duckstation exe found via DirectoryService');
    }

    // 2. Dynamic path resolution for macOS/Windows/Linux
    final String resolvedPath;
    if (_platform.isWindows) {
      final localAppData = _platform.environment['LOCALAPPDATA'] ?? '';
      resolvedPath = p.join(localAppData, 'DuckStation');
    } else {
      resolvedPath = await _directoryService.getEmulatorAppSupportDirectory('DuckStation', platformSlug: platformSlug);
    }

    debugPrint('[DuckStation] standard install base candidate: $resolvedPath');
    if (!await io.Directory(resolvedPath).exists()) {
      throw Exception('Save directory not found for DuckStation at $resolvedPath. Please launch DuckStation at least once to generate save data.');
    }
    return resolvedPath;
  }

  // ─── Memory cards ─────────────────────────────────────────────────────────
  //
  // DuckStation names a game's card by its "Memory Card Type" setting
  // (`[MemoryCards] CardNType`, overridable per game in
  // `gamesettings/<SERIAL>.ini`): `<serial>_N.mcd`, `<title>_N.mcd` (the
  // `saveName` in its own gamedb.yaml) or `<ROM file name>_N.mcd`, N being
  // the port. Freegosy reads that setting, uploads exactly those cards, and
  // restores a card under the name *this* PC's DuckStation will open, so PCs
  // set to different types still share the save.
  //
  // A card shared by every game is never uploaded or restored whole (that
  // would roll back all other games): the push extracts this game's saves
  // into a card of their own, `<serial>_N.mcd`, which a per-game PC restores
  // like any card; the pull replaces this game's saves on the local shared
  // card and leaves every other save as it is (see Ps1MemoryCard).

  static const _noCardMessage =
      'DuckStation has no memory card that keeps saves ("No Memory Card" or '
      '"Non-Persistent"), so there is nothing to sync.';

  Future<_CardSetup> _cardSetup(Game game, String romPath, {bool needSerial = true}) async {
    final baseDir = await _getBaseDir(platformSlug: game.platformSlug);
    final serial = needSerial ? await _serial(game, romPath) : null;
    final globalIni = await _readIfExists(p.join(baseDir, 'settings.ini'));
    final gameIni =
        serial == null ? null : await _readIfExists(p.join(baseDir, 'gamesettings', '$serial.ini'));
    final config = DuckstationMemcardConfig.fromIni(globalIni, gameIni);
    final directory = config.directory;
    final memcardsDir = directory == null
        ? p.join(baseDir, 'memcards')
        : (p.isAbsolute(directory) ? directory : p.join(baseDir, directory));
    return _CardSetup(memcardsDir: memcardsDir, config: config, serial: serial);
  }

  static Future<String?> _readIfExists(String path) async {
    try {
      final file = File(path);
      return await file.exists() ? await file.readAsString() : null;
    } catch (e) {
      debugPrint('[DuckStation] cannot read $path: $e');
      return null;
    }
  }

  /// DuckStation's installed `resources` folder (holding gamedb.yaml), or
  /// null when it can't be found (e.g. inside an AppImage).
  Future<String?> _resourcesDir() async {
    final exePath = await _directoryService.findEmulatorExecutable('duckstation', _getEmuExe());
    if (exePath == null) return null;
    final exeDir = File(exePath).parent;
    for (final dir in [
      p.join(exeDir.path, 'resources'),
      if (_platform.isMacOS) p.join(exeDir.parent.path, 'Resources'),
    ]) {
      if (await File(p.join(dir, 'gamedb.yaml')).exists()) return dir;
    }
    return null;
  }

  /// The exact name (without `_N.mcd`) DuckStation gives [game]'s card of
  /// [type], or null when it can't be known: the serial couldn't be read,
  /// or (by title) the game database doesn't know the game.
  Future<String?> _cardName(_CardSetup setup, DuckstationCardType type, Game game, String romPath, int port) async {
    switch (type) {
      case DuckstationCardType.perGameSerial:
        return setup.serial;
      case DuckstationCardType.perGameFileTitle:
        final title = await FileSystemEntity.isDirectory(romPath)
            ? getRomStem(game)
            : p.basenameWithoutExtension(romPath);
        return duckstationSafeFileName(title, _platform);
      case DuckstationCardType.perGameTitle:
        final serial = setup.serial;
        final resources = serial == null ? null : await _resourcesDir();
        if (serial == null || resources == null) return null;
        final discTitle = await DuckstationGameDb.saveTitle(resources, serial, usePlaylistTitle: false);
        final setTitle = setup.config.usePlaylistTitle ? await DuckstationGameDb.discSetTitle(resources, serial) : null;
        if (setTitle == null || discTitle == null) {
          final title = setTitle ?? discTitle;
          return title == null ? null : duckstationSafeFileName(title, _platform);
        }
        // A multi-disc game shares the disc set's card, but, as DuckStation
        // does, a card already made under this disc's own title wins.
        final discName = duckstationSafeFileName(discTitle, _platform);
        if (await File(p.join(setup.memcardsDir, '${discName}_$port.mcd')).exists()) return discName;
        return duckstationSafeFileName(setTitle, _platform);
      default:
        return null;
    }
  }

  /// [game]'s card for [port] on disk, or null when there is none.
  Future<File?> _localCard(_CardSetup setup, Game game, String romPath, int port) async {
    final type = setup.config.typeOf(port);
    final name = await _cardName(setup, type, game, romPath, port);
    if (name != null) {
      final file = File(p.join(setup.memcardsDir, '${name}_$port.mcd'));
      return await file.exists() ? file : null;
    }
    if (type == DuckstationCardType.perGameTitle) {
      debugPrint('[DuckStation]   title unknown to the game database — matching cards by name');
      return _cardByTitleWords(setup.memcardsDir, game, port);
    }
    debugPrint('[DuckStation]   serial unknown — no ${type.iniValue} card name for port $port');
    return null;
  }

  /// Fallback when the card title isn't known: the newest card for [port]
  /// whose name contains every word (3+ letters) of the ROM name without its
  /// tags. Word matching avoids "final fantasy vii" matching "... viii";
  /// multi-disc `.m3u` names like "Final Fantasy VII (USA).m3u" match
  /// "Final Fantasy VII_1.mcd" (issue #62).
  Future<File?> _cardByTitleWords(String memcardsDir, Game game, int port) async {
    final dir = Directory(memcardsDir);
    if (!await dir.exists()) return null;
    final stemTokens =
        _words(normalizeSaveMatchName(getRomStem(game))).where((w) => w.length >= 3).toList();
    if (stemTokens.isEmpty) return null;
    final suffix = '_$port.mcd';
    File? best;
    DateTime? bestModified;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final base = p.basename(entity.path);
      final lower = base.toLowerCase();
      if (!lower.endsWith(suffix) || lower.startsWith('shared_card_')) continue;
      final cardTokens = _words(normalizeSaveMatchName(base.substring(0, base.length - suffix.length)));
      if (!stemTokens.every(cardTokens.contains)) continue;
      final modified = await entity.lastModified();
      if (best == null || modified.isAfter(bestModified!)) {
        best = entity;
        bestModified = modified;
      }
    }
    return best;
  }

  static List<String> _words(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();

  /// The port a card was made for: the `_N` of `<name>_N.mcd` or
  /// `shared_card_N.mcd`, the N of a legacy `McdN.mcd`, else port 1.
  static int _portOf(String fileName) {
    final base = p.basename(fileName).toLowerCase();
    final match =
        RegExp(r'_(\d+)\.mcd$').firstMatch(base) ?? RegExp(r'^mcd(\d+)\.mcd$').firstMatch(base);
    final port = match == null ? null : int.tryParse(match.group(1)!);
    return port != null && DuckstationMemcardConfig.ports.contains(port) ? port : 1;
  }

  /// A memory card upload: DuckStation's `.mcd`, or the `<ROM name>.srm`
  /// RetroArch keeps a PS1 card in (what Argosy uploads) when it really is a
  /// raw 128 KB card. An `.srm` has no port in its name: it is port 1.
  static bool _isCardUpload(String fileName, Uint8List bytes) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mcd')) return true;
    return lower.endsWith('.srm') && Ps1MemoryCard.looksLikeCard(bytes);
  }

  static bool _isSharedCardName(String fileName) {
    final base = p.basename(fileName).toLowerCase();
    return base.startsWith('shared_card_') || RegExp(r'^mcd\d+\.mcd$').hasMatch(base);
  }

  @override
  Future<String?> saveSyncBlockedReason(Game game, String romPath) async {
    try {
      final config = (await _cardSetup(game, romPath)).config;
      final syncable = config.portsOfType((t) => t.isPerGame || t == DuckstationCardType.shared);
      return syncable.isEmpty ? _noCardMessage : null;
    } catch (e) {
      debugPrint('[DuckStation] cannot tell whether saves can be synced: $e');
      return null;
    }
  }

  /// A pull into a card shared by all games rewrites that card: it must be
  /// done before DuckStation opens it.
  @override
  Future<bool> pullMustFinishBeforeLaunch(Game game, String romPath) async {
    try {
      final config = (await _cardSetup(game, romPath)).config;
      return config.portsOfType((t) => t == DuckstationCardType.shared).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async =>
      (await _cardSetup(game, romPath, needSerial: false)).memcardsDir;

  File _sharedCard(_CardSetup setup, int port) =>
      File(p.join(setup.memcardsDir, setup.config.cardPaths[port] ?? 'shared_card_$port.mcd'));

  /// Whether a save on a memory card belongs to [game]: its directory name
  /// (e.g. `BESLES-02605-SETTING`) carries the game's product code after a
  /// two-letter region, and a multi-disc game's discs read each other's.
  /// Null when the serial can't be read.
  Future<bool Function(String name)?> _savesOfGame(_CardSetup setup) async {
    final serial = setup.serial;
    if (serial == null) return null;
    final resources = await _resourcesDir();
    final serials = resources == null
        ? [serial]
        : await DuckstationGameDb.discSetSerials(resources, serial);
    final keys = {for (final s in serials) _serialKey(s)};
    return (name) => name.length >= 12 && keys.contains(_serialKey(name.substring(2, 12)));
  }

  static bool Function(File) _changedSince(DateTime? sessionStart) => (file) =>
      sessionStart == null ||
      !file.statSync().modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)));

  /// What local backups keep: this game's own cards, and any shared card
  /// whole (a backup is restored by hand, as a whole card).
  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final setup = await _cardSetup(game, romPath);
    final changed = _changedSince(sessionStart);
    final result = [for (final (_, card) in await _perGameCards(setup, game, romPath, changed)) card];
    for (final port in setup.config.portsOfType((t) => t == DuckstationCardType.shared)) {
      final card = _sharedCard(setup, port);
      if (await card.exists() && changed(card)) result.add(card);
    }
    // Save states are not part of the save: they sync separately through
    // StateSyncService (see [StateSyncCapable]).
    return result;
  }

  /// What sync uploads: this game's own cards, and for a shared card a card
  /// holding only this game's saves. The port-1 card goes up as
  /// `<ROM name>.srm`: the same bytes under the name RetroArch's PS1 cores,
  /// Argosy and RomM's player use for a PS1 card (docs/save-interop.md);
  /// other ports keep DuckStation's `<name>_N.mcd`. Restoring takes both.
  @override
  Future<Map<File, File?>> getSaveFilesWithScreenshots(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final setup = await _cardSetup(game, romPath);
    final changed = _changedSince(sessionStart);
    final result = <File>[];
    for (final (port, card) in await _perGameCards(setup, game, romPath, changed)) {
      result.add(port == 1
          ? await _writeUpload(game, _srmName(game), await card.readAsBytes())
          : card);
    }
    final sharedPorts = setup.config.portsOfType((t) => t == DuckstationCardType.shared).toList();
    final belongs = sharedPorts.isEmpty ? null : await _savesOfGame(setup);
    for (final port in sharedPorts) {
      final shared = _sharedCard(setup, port);
      if (belongs == null) {
        debugPrint('[DuckStation]   port $port (Shared): serial unknown — can\'t tell this game\'s saves');
      } else if (!await shared.exists() || !changed(shared)) {
        debugPrint('[DuckStation]   port $port (Shared): ${shared.path} not written this session');
      } else {
        final name = port == 1 ? _srmName(game) : '${setup.serial}_$port.mcd';
        final extracted = await _extractToTemp(game, name, port, shared, belongs);
        if (extracted != null) result.add(extracted);
      }
    }
    return {for (final f in result) f: null};
  }

  /// `<ROM name>.srm`, the name a PS1 card has in RetroArch.
  /// The upload's name, safe on every OS the save may be pulled to.
  String _srmName(Game game) =>
      '${duckstationSafeFileName(getRomStem(game), const PlatformInfo('windows'))}.srm';

  /// Writes [bytes] as [name] in this game's temporary upload folder.
  static Future<File> _writeUpload(Game game, String name, List<int> bytes) async {
    final dir = Directory(p.join(Directory.systemTemp.path, 'freegosy_duckstation',
        game.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')));
    await dir.create(recursive: true);
    final out = File(p.join(dir.path, name));
    await out.writeAsBytes(bytes);
    return out;
  }

  /// This game's own cards on disk, with their ports.
  Future<List<(int, File)>> _perGameCards(
      _CardSetup setup, Game game, String romPath, bool Function(File) changed) async {
    final config = setup.config;
    debugPrint('[DuckStation] memory cards: ${setup.memcardsDir}  serial=${setup.serial}  '
        'types=${DuckstationMemcardConfig.ports.map((port) => config.typeOf(port).iniValue).join(",")}');
    final result = <(int, File)>[];
    for (final port in config.portsOfType((t) => t.isPerGame)) {
      final card = await _localCard(setup, game, romPath, port);
      if (card == null) {
        debugPrint('[DuckStation]   port $port (${config.typeOf(port).iniValue}): no card on disk');
      } else if (changed(card)) {
        debugPrint('[DuckStation]   port $port (${config.typeOf(port).iniValue}): ${card.path}');
        result.add((port, card));
      }
    }
    return result;
  }

  /// This game's saves from [shared], as a card of their own in a temporary
  /// file called [name]; null when there are none or the card can't be read.
  Future<File?> _extractToTemp(
      Game game, String name, int port, File shared, bool Function(String) belongs) async {
    try {
      final card = Ps1MemoryCard.parse(await shared.readAsBytes());
      final mine = card.saves.where((s) => belongs(s.name)).map((s) => s.name).toList();
      if (mine.isEmpty) {
        debugPrint('[DuckStation]   port $port (Shared): no saves of this game on ${shared.path}');
        return null;
      }
      final out = await _writeUpload(game, name, card.extract(belongs));
      debugPrint('[DuckStation]   port $port (Shared): ${mine.length} save(s) of this game → ${out.path}: $mine');
      return out;
    } on FormatException catch (e) {
      debugPrint('[DuckStation]   port $port (Shared): ${shared.path} is not a memory card DuckStation '
          'wrote as expected ($e) — not uploading it');
      return null;
    }
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final cards = <(String, Uint8List)>[];
      if (filename.toLowerCase().endsWith('.zip')) {
        for (final entry in ZipDecoder().decodeBytes(data)) {
          if (!entry.isFile) continue;
          // Only memory cards are restored from a saves bundle. Older
          // Freegosy versions bundled `savestates/` into it; states now sync
          // separately through StateSyncService, so never write them here.
          final content = Uint8List.fromList(entry.content as List<int>);
          if (!_isCardUpload(entry.name, content)) {
            debugPrint('[DuckStation]   skipping non-memcard entry: ${entry.name}');
            continue;
          }
          cards.add((p.basename(entry.name), content));
        }
      } else if (_isCardUpload(filename, data)) {
        cards.add((p.basename(filename), data));
      } else {
        debugPrint('[DuckStation]   ignoring non-memcard save upload: $filename');
        return true;
      }
      // A game's own card wins over a shared one uploaded for the same port
      // by older versions: write the shared ones first.
      cards.sort((a, b) => (_isSharedCardName(a.$1) ? 0 : 1) - (_isSharedCardName(b.$1) ? 0 : 1));

      final setup = await _cardSetup(game, destPath);
      for (final (name, bytes) in cards) {
        final port = _portOf(name);
        final type = setup.config.typeOf(port);
        if (type == DuckstationCardType.shared) {
          await _mergeIntoShared(setup, port, name, bytes);
          continue;
        }
        if (!type.isPerGame) {
          debugPrint('[DuckStation]   skipping $name: port $port is ${type.iniValue} here');
          continue;
        }
        final target = await _restoreTarget(setup, game, destPath, port);
        if (target == null) {
          debugPrint('[DuckStation]   skipping $name: no ${type.iniValue} card name for this game');
          continue;
        }
        debugPrint('[DuckStation]   restoring $name → ${target.path}');
        await target.parent.create(recursive: true);
        await backupSave(target.path);
        await target.writeAsBytes(await _onlyThisGame(setup, name, bytes));
      }
      return true;
    } on SaveSyncNotPossibleException {
      rethrow;
    } catch (e) {
      debugPrint('[DuckStation] restoreSave failed: $e');
      return false;
    }
  }

  /// An old upload of a whole shared card, cut down to this game's saves
  /// before it becomes this game's own card. Anything else as it is.
  Future<Uint8List> _onlyThisGame(_CardSetup setup, String name, Uint8List bytes) async {
    if (!_isSharedCardName(name)) return bytes;
    final belongs = await _savesOfGame(setup);
    if (belongs == null) return bytes;
    try {
      final card = Ps1MemoryCard.parse(bytes);
      if (!card.saves.any((s) => belongs(s.name))) return bytes;
      debugPrint('[DuckStation]   $name is a whole shared card — keeping only this game\'s saves');
      return card.extract(belongs);
    } on FormatException {
      return bytes;
    }
  }

  /// Replaces this game's saves on the local shared card of [port] with those
  /// on [bytes]; every other game's save stays as it is. Written to a
  /// temporary file and swapped in, after a `.bak` of the old card.
  Future<void> _mergeIntoShared(_CardSetup setup, int port, String name, Uint8List bytes) async {
    final belongs = await _savesOfGame(setup);
    if (belongs == null) {
      debugPrint('[DuckStation]   skipping $name: serial unknown — can\'t tell this game\'s saves');
      return;
    }
    final shared = _sharedCard(setup, port);
    final Ps1MemoryCard incoming;
    try {
      incoming = Ps1MemoryCard.parse(bytes);
    } on FormatException catch (e) {
      throw SaveSyncNotPossibleException(
          "The memory card from RomM ($name) isn't a PS1 memory card Freegosy can read ($e). "
          'Nothing was changed.');
    }
    final Ps1MemoryCard local;
    try {
      local = Ps1MemoryCard.parse(
          await shared.exists() ? await shared.readAsBytes() : Ps1MemoryCard.formatted());
    } on FormatException catch (e) {
      throw SaveSyncNotPossibleException(
          "DuckStation's shared memory card (${p.basename(shared.path)}) doesn't look like a PS1 "
          'memory card Freegosy can safely change ($e), so it was left as it is.');
    }
    final Uint8List? merged;
    try {
      merged = local.replaceSaves(incoming, belongs);
    } on Ps1CardFullException catch (e) {
      throw SaveSyncNotPossibleException(
          "The save from RomM needs ${e.needed} blocks, but DuckStation's shared memory card "
          '(${p.basename(shared.path)}) has only ${e.free} free. Nothing was changed. Free some '
          "blocks in DuckStation's Memory Card Editor, then pull again.");
    }
    if (merged == null) {
      debugPrint('[DuckStation]   $name holds no saves of this game — ${shared.path} left as it is');
      return;
    }
    if (SaveRestoreGuard.restoreTooLate) {
      debugPrint('[DuckStation]   DuckStation has started without this pull — ${shared.path} left as it is');
      return;
    }
    await shared.parent.create(recursive: true);
    if (await shared.exists()) await backupSave(shared.path);
    final temp = File('${shared.path}.freegosy_tmp');
    await temp.writeAsBytes(merged, flush: true);
    await temp.rename(shared.path);
    debugPrint('[DuckStation]   merged this game\'s saves from $name into ${shared.path}: '
        '${incoming.saves.where((s) => belongs(s.name)).map((s) => s.name).toList()}');
  }

  /// Where [game]'s card for [port] goes on this PC: the exact name when
  /// known; by title, an existing card matched by name, else the ROM name
  /// without its tags (DuckStation's database title usually reads the same).
  Future<File?> _restoreTarget(_CardSetup setup, Game game, String romPath, int port) async {
    final type = setup.config.typeOf(port);
    final name = await _cardName(setup, type, game, romPath, port);
    if (name != null) return File(p.join(setup.memcardsDir, '${name}_$port.mcd'));
    if (type != DuckstationCardType.perGameTitle) return null;
    final existing = await _cardByTitleWords(setup.memcardsDir, game, port);
    if (existing != null) return existing;
    final guess = duckstationSafeFileName(normalizeSaveMatchName(getRomStem(game)), _platform);
    debugPrint('[DuckStation]   title unknown to the game database — naming the card "$guess"');
    return guess.isEmpty ? null : File(p.join(setup.memcardsDir, '${guess}_$port.mcd'));
  }
}

/// What [DuckstationSaveStrategy] needs to name a game's memory cards.
class _CardSetup {
  _CardSetup({required this.memcardsDir, required this.config, required this.serial});
  final String memcardsDir;
  final DuckstationMemcardConfig config;
  final String? serial;
}
