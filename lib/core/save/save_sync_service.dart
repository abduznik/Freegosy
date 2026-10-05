import 'dart:io' as io;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../storage/app_preferences.dart';
import '../romm/romm_models.dart';
import '../romm/romm_service.dart';
import '../storage/directory_service.dart';
import 'formats/rzip.dart';
import 'formats/save_format_registry.dart';
import 'formats/zstd.dart';
import 'romm_content_hash.dart';
import 'save_content_hash.dart';
import 'save_strategy.dart';
import 'strategy_lock.dart';
import 'strategies/retroarch_save_strategy.dart';
import 'strategies/dolphin_save_strategy.dart';
import 'strategies/eden_save_strategy.dart';
import 'strategies/ryujinx_save_strategy.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'strategies/windows_save_strategy.dart';
import 'strategies/pcsx2_save_strategy.dart';
import 'strategies/rpcs3_save_strategy.dart';
import 'strategies/xenia_save_strategy.dart';
import 'strategies/duckstation_save_strategy.dart';
import 'strategies/ares_save_strategy.dart';
import 'strategies/melonds_save_strategy.dart';
import 'strategies/mgba_save_strategy.dart';
import 'strategies/ppsspp_save_strategy.dart';
import 'strategies/cemu_save_strategy.dart';
import 'strategies/azahar_save_strategy.dart';
import '../emulator/strategy_registry.dart';
import '../platform/platform_info.dart';

/// A save the user chose could not be put in place; [message] says why, in
/// words for the user.
class SaveChoiceException implements Exception {
  SaveChoiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SaveConflictException implements Exception {
  final Game game;
  final DateTime localTime;
  final DateTime cloudTime;
  final String? localScreenshot;
  final String? cloudScreenshot;
  
  SaveConflictException({
    required this.game, 
    required this.localTime, 
    required this.cloudTime,
    this.localScreenshot,
    this.cloudScreenshot,
  });
  
  @override
  String toString() => 'Conflict detected for ${game.name}: Local ($localTime) vs Cloud ($cloudTime)';
}

class SaveSyncService {
  final RommService _rommService;
  final DirectoryService _directoryService;
  final StrategyRegistry _strategyRegistry;
  final AppPreferences _prefs;

  /// Decompresses zstd RZIP chunks; the zstandard plugin when null.
  final ZstdDecompressor? _zstd;

  /// One save operation at a time: the strategies are shared by every game.
  final _lock = StrategyLock();

  final _activity = ValueNotifier<String?>(null);

  /// What the save operation holding the lock does, in words for the user
  /// (e.g. "Uploading Mario Kart 64's save"), while an upload or download
  /// runs; null otherwise. Screens waiting for the lock show it.
  ValueListenable<String?> get activity => _activity;

  @visibleForTesting
  void debugSetActivity(String? value) => _activity.value = value;

  /// What runs, newest last: operations can overlap inside one hold of the
  /// lock and end in any order.
  final _activities = <(Object, String)>[];

  /// Runs [body] with [activity] set to [what].
  Future<T> _doing<T>(String what, Future<T> Function() body) async {
    final token = Object();
    _activities.add((token, what));
    _activity.value = what;
    try {
      return await body();
    } finally {
      _activities.removeWhere((a) => identical(a.$1, token));
      _activity.value = _activities.isEmpty ? null : _activities.last.$2;
    }
  }

  /// Minimum save file size in bytes to consider valid for upload.
  /// Files smaller than this are likely empty/blank saves created by an
  /// emulator that didn't actually save, and should not overwrite a
  /// legitimate cloud save (issues #42, #24).
  static const int minValidSaveSizeBytes = 100;

  late final RetroArchSaveStrategy _retroarch;
  late final DolphinSaveStrategy _dolphin;
  late final EdenSaveStrategy _eden;
  late final RyujinxSaveStrategy _ryujinx;
  late final WindowsSaveStrategy _windows;
  late final Pcsx2SaveStrategy _pcsx2;
  late final Rpcs3SaveStrategy _rpcs3;
  late final XeniaSaveStrategy _xenia;
  late final DuckstationSaveStrategy _duckstation;
  late final MelonDsSaveStrategy _melonds;
  late final MgbaSaveStrategy _mgba;
  late final PpssppSaveStrategy _ppsspp;
  late final CemuSaveStrategy _cemu;
  late final AzaharSaveStrategy _azahar;
  late final AresSaveStrategy _ares;

  /// [platform] is the OS the strategies look for emulators on; tests pass
  /// one with a temporary home.
  SaveSyncService(this._rommService, this._directoryService, this._strategyRegistry, this._prefs,
      {ZstdDecompressor? zstd, PlatformInfo? platform})
      : _zstd = zstd {
    _retroarch = RetroArchSaveStrategy(_directoryService, prefs: _prefs, platform: platform);
    _dolphin = DolphinSaveStrategy(_directoryService, platform: platform);
    _eden = EdenSaveStrategy(_directoryService, onMappingResolved: saveMappedFolder, platform: platform);
    _ryujinx = RyujinxSaveStrategy(onMappingResolved: saveMappedFolder, platform: platform);
    _windows = WindowsSaveStrategy(_prefs, platform: platform);
    _pcsx2 = Pcsx2SaveStrategy(_directoryService, _prefs, platform: platform);
    _rpcs3 = Rpcs3SaveStrategy(_directoryService, platform: platform);
    _xenia = XeniaSaveStrategy(_directoryService, platform: platform);
    _duckstation = DuckstationSaveStrategy(_directoryService, _prefs, platform: platform);
    _melonds = MelonDsSaveStrategy(_directoryService, platform: platform);
    _mgba = MgbaSaveStrategy(_directoryService, platform: platform);
    _ppsspp = PpssppSaveStrategy(_directoryService, platform: platform);
    _cemu = CemuSaveStrategy(_directoryService, platform: platform);
    _azahar = AzaharSaveStrategy(_directoryService, onMappingResolved: saveMappedFolder, platform: platform);
    _ares = AresSaveStrategy(_directoryService, platform: platform);
  }

  /// Returns the manual Title ID mapping for a given game.
  String? getMappedFolder(String gameId) {
    return _prefs.getString('eden_mapping_$gameId');
  }

  /// Saves the manual Title ID mapping for a given game.
  Future<void> saveMappedFolder(String gameId, String folderName) async {
    await _prefs.setString('eden_mapping_$gameId', folderName);
  }

  /// Returns the manual Eden profile choice.
  String? getActiveProfile() {
    return _prefs.getString('active_eden_profile');
  }

  /// Saves the manual Eden profile choice.
  Future<void> saveActiveProfile(String profileId) async {
    await _prefs.setString('active_eden_profile', profileId);
  }

  /// Returns the appropriate save strategy for [platformSlug], or null if unsupported.
  ///
  /// If [emulatorId] is given, resolves the strategy for that specific
  /// emulator instead of the platform's globally-configured preference.
  /// Callers that know which emulator actually launched the game (e.g. via
  /// the per-game emulator picker) must pass it here — otherwise sync can
  /// silently read/write the wrong emulator's save folder when the launch
  /// emulator differs from the platform-wide default (issue #79).
  SaveStrategy? getStrategyForSlug(String? platformSlug, {String? emulatorId}) {
    debugPrint('[SaveSync] Resolving strategy for slug="$platformSlug" emulatorId=$emulatorId');
    if (emulatorId != null) {
      final strategy = _saveStrategyForEmulatorId(emulatorId);
      debugPrint('[SaveSync]   → explicit emulator="$emulatorId" → strategy=${strategy?.strategyId ?? "none"}');
      if (strategy != null) return strategy;
    }
    if (platformSlug != null) {
      final preferredId = _strategyRegistry.getPreferredEmulatorId(platformSlug);
      if (preferredId != null) {
        final strategy = _saveStrategyForEmulatorId(preferredId);
        debugPrint('[SaveSync]   → preferred emulator="$preferredId" → strategy=${strategy?.strategyId ?? "none"}');
        return strategy;
      }

      // No user preference set: check which emulator the registry would use
      // by default (first registered strategy that supports this slug).
      final defaultEmulatorStrategy = _strategyRegistry.getStrategyForSlug(platformSlug);
      if (defaultEmulatorStrategy != null) {
        final strategy = _saveStrategyForEmulatorId(defaultEmulatorStrategy.emulatorId);
        debugPrint('[SaveSync]   → default emulator="${defaultEmulatorStrategy.emulatorId}" → strategy=${strategy?.strategyId ?? "none"}');
        return strategy;
      }
    }

    // Hardcoded fallback (should rarely be reached)
    debugPrint('[SaveSync]   → no registry match, using hardcoded fallback');
    switch (platformSlug?.toLowerCase()) {
      case 'gba':
      case 'gbc':
      case 'gb':
      case 'game-boy-advance':
      case 'game-boy-color':
      case 'game-boy':
        return _mgba;
      case 'snes':
      case 'nes':
      case 'n64':
      case 'megadrive':
      case 'genesis':
      case 'md':
      case 'sms':
      case 'mastersystem':
        return _retroarch;
      case 'nds':
      case 'nintendo-ds':
      case 'ds':
        return _melonds;
      case 'psp':
      case 'playstation-portable':
        return _ppsspp;
      case 'ps1':
      case 'playstation':
      case 'psx':
        return _duckstation;
      case 'dc':
      case 'dreamcast':
        return _retroarch;
      case 'gc':
      case 'ngc':
      case 'gamecube':
      case 'wii':
        return _dolphin;
      case 'switch':
      case 'nintendo-switch':
      case 'ns':
        return _ryujinx; // Default Switch to Ryujinx
      case 'windows':
      case 'pc':
      case 'win':
        return _windows;
      case 'ps2':
      case 'playstation-2':
      case 'playstation2':
        return _pcsx2;
      case 'ps3':
      case 'playstation-3':
      case 'playstation3':
        return _rpcs3;
      case 'xbox360':
      case 'xbla':
        return _xenia;
      case 'wiiu':
      case 'wii-u':
      case 'nintendo-wii-u':
      case 'nintendo-wiiu':
        return _cemu;
      case '3ds':
      case 'n3ds':
      case 'nintendo-3ds':
      case 'nintendo3ds':
      case 'new-nintendo-3ds':
      case 'new-nintendo-3ds-xl':
        return _azahar;
      default:
        debugPrint('[SaveSync]   → no strategy for slug="$platformSlug"');
        return null;
    }
  }

  /// Returns the appropriate save strategy for [game], honoring its
  /// per-game emulator preference before falling back to [getStrategyForSlug]'s
  /// platform-wide resolution.
  ///
  /// [emulatorId], if passed, still wins over any stored preference (it's the
  /// emulator that actually launched this session, e.g. from the per-game
  /// picker) — this only fills in the per-game preference for callers that
  /// don't already know which emulator launched the game (see issue #79).
  SaveStrategy? getStrategyForGame(Game game, {String? emulatorId}) {
    final resolvedEmulatorId =
        emulatorId ?? _strategyRegistry.getGameEmulatorPreference(game.id);
    return getStrategyForSlug(game.platformSlug, emulatorId: resolvedEmulatorId);
  }

  /// Runs [body] with the save strategy of [emulatorId] (else the game's
  /// emulator) set up for [game], with no other save operation in between:
  /// the strategies are shared by every game. Null when there is none.
  Future<T?> withStrategy<T>(Game game, Future<T> Function(SaveStrategy strategy) body,
          {String? emulatorId, String? coreOverride}) =>
      _lock.run(() async {
        final strategy = emulatorId != null ? _saveStrategyForEmulatorId(emulatorId) : getStrategyForGame(game);
        if (strategy == null) return null;
        _applyStrategyMappings(strategy, game,
            coreOverride: coreOverride ?? _strategyRegistry.getGameCorePreference(game.id));
        return body(strategy);
      });

  /// Runs [body] with no other save operation in between (the save lock),
  /// for services that use the strategies themselves (state sync, resume).
  /// [doing] says what it does, for screens waiting for the lock (see
  /// [activity]).
  Future<T> exclusive<T>(Future<T> Function() body, {String? doing}) =>
      _lock.run(() => doing == null ? body() : _doing(doing, body));

  /// getStrategyForGame, set up for [game] (RetroArch: [coreOverride], else
  /// the game's chosen core). Call it inside [exclusive]: the strategies are
  /// shared by every game.
  SaveStrategy? strategyForGame(Game game, {String? emulatorId, String? coreOverride}) {
    final strategy = getStrategyForGame(game, emulatorId: emulatorId);
    if (strategy != null) {
      _applyStrategyMappings(strategy, game,
          coreOverride: coreOverride ?? _strategyRegistry.getGameCorePreference(game.id));
    }
    return strategy;
  }

  /// The save strategy of the emulator [emulatorId] exactly; null when it
  /// has none (unlike getStrategyForSlug, never falls back to another).
  SaveStrategy? saveStrategyForEmulator(String emulatorId) => _saveStrategyForEmulatorId(emulatorId);

  /// Where [emulatorId] keeps [game]'s saves; null when it can't tell.
  Future<String?> saveDirFor(Game game, String romPath, {required String emulatorId, String? coreOverride}) =>
      _lock.run(() => _saveDirForUnlocked(game, romPath, emulatorId: emulatorId, coreOverride: coreOverride));

  Future<String?> _saveDirForUnlocked(Game game, String romPath, {required String emulatorId, String? coreOverride}) async {
    try {
      return await _saveStrategyFor(game, emulatorId, coreOverride: coreOverride)?.getSaveDir(game, romPath);
    } catch (e) {
      debugPrint('[SaveSync] save folder of $emulatorId unknown: $e');
      return null;
    }
  }

  /// [emulatorId]'s save strategy, set up for [game]: RetroArch's core
  /// ([coreOverride], else the game's chosen core), Eden/Ryujinx/Azahar
  /// mapped folders. The strategies are shared by every game, so a caller
  /// must use this, not saveStrategyForEmulator, before reading or writing.
  SaveStrategy? _saveStrategyFor(Game game, String emulatorId, {String? coreOverride}) {
    final strategy = _saveStrategyForEmulatorId(emulatorId);
    if (strategy != null) {
      _applyStrategyMappings(strategy, game,
          coreOverride: coreOverride ?? _strategyRegistry.getGameCorePreference(game.id));
    }
    return strategy;
  }

  /// Maps an emulator strategy ID to the corresponding save strategy.
  SaveStrategy? _saveStrategyForEmulatorId(String emulatorId) {
    final id = emulatorId.toLowerCase();
    if (id == 'melonds') return _melonds;
    if (id == 'mgba') return _mgba;
    if (id == 'duckstation') return _duckstation;
    if (id == 'retroarch') return _retroarch;
    if (id == 'ppsspp') return _ppsspp;
    if (id == 'cemu') return _cemu;
    if (id == 'pcsx2') return _pcsx2;
    if (id == 'rpcs3') return _rpcs3;
    if (id == 'dolphin') return _dolphin;
    if (id == 'xenia' || id == 'xenia_canary') return _xenia;
    if (id == 'eden') return _eden;
    if (id == 'ryujinx') return _ryujinx;
    if (id == 'windows_native') return _windows;
    if (id == 'azahar') return _azahar;
    if (id == 'ares') return _ares;
    return null;
  }

  String _hashKey(String gameId, String filename) =>
      'last_hash_${gameId}_$filename';

  String? _getStoredHash(
      String gameId, String filename) {
    return _prefs.getString(_hashKey(gameId, filename));
  }

  Future<void> _storeHash(
      String gameId, String filename, String hash) async {
    await _prefs.setString(_hashKey(gameId, filename), hash);
  }

  /// Clears the stored hash for a game, forcing the next push to upload.
  Future<void> clearHashCache(String gameId) async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('last_hash_${gameId}_')).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
    debugPrint('[SaveSync] Cleared hash cache for game $gameId');
  }

  Future<String> _hashFile(io.File file) => md5OfFile(file);

  /// The `content_hash` RomM would give [emulatorId]'s current save for
  /// [game] if it were pushed now (see romm_content_hash.dart): the files a
  /// push gathers, RZIP unpacked, one file by its bytes, several as the zip
  /// a push uploads. Null when there are none or they can't be read.
  Future<String?> rommHashOfLocal(Game game, String romPath,
          {required String emulatorId, String syncMode = 'saves', String? coreOverride}) =>
      _lock.run(() async {
        final strategy = _saveStrategyFor(game, emulatorId, coreOverride: coreOverride);
        return strategy == null ? null : _rommHashOf(strategy, game, romPath, syncMode);
      });

  /// rommHashOfLocal for a [strategy] already set up for [game].
  Future<String?> _rommHashOf(SaveStrategy strategy, Game game, String romPath, String syncMode) async {
    try {
      final filesMap = await _uploadFiles(strategy, game, romPath, syncMode);
      return filesMap.isEmpty ? null : await _rommHashOfFiles(strategy, game, romPath, filesMap);
    } catch (e) {
      debugPrint('[SaveSync] RomM hash of ${game.displayName}\'s save not taken: $e');
      return null;
    }
  }

  /// rommHashOfLocal for both sync modes ('saves', and 'both' with the
  /// states), under one hold of the save lock, hashed once when both modes
  /// upload the same files.
  Future<Set<String>> rommHashesOfLocal(Game game, String romPath, {required String emulatorId, String? coreOverride}) =>
      _lock.run(() async {
        final strategy = _saveStrategyFor(game, emulatorId, coreOverride: coreOverride);
        if (strategy == null) return const <String>{};
        final hashes = <String>{};
        String? lastFiles;
        String? lastHash;
        for (final mode in const ['saves', 'both']) {
          try {
            final filesMap = await _uploadFiles(strategy, game, romPath, mode);
            if (filesMap.isEmpty) continue;
            final files = (filesMap.keys.map((f) => f.path).toList()..sort()).join('|');
            final hash = files == lastFiles ? lastHash : await _rommHashOfFiles(strategy, game, romPath, filesMap);
            lastFiles = files;
            lastHash = hash;
            if (hash != null) hashes.add(hash);
          } catch (e) {
            debugPrint('[SaveSync] RomM hash of ${game.displayName}\'s save ($mode) not taken: $e');
          }
        }
        return hashes;
      });

  /// The files a push in [syncMode] uploads: the strategy's, filtered, RZIP
  /// unpacked.
  Future<Map<io.File, io.File?>> _uploadFiles(SaveStrategy strategy, Game game, String romPath, String syncMode) async {
    final filesMap =
        _filterFilesMap(strategy, await strategy.getSaveFilesWithScreenshots(game, romPath, syncMode: syncMode));
    return filesMap.isEmpty ? filesMap : _unrzipFiles(game, filesMap);
  }

  /// RomM's hash of [filesMap] as a push uploads it: one file by itself (a
  /// zip by its contents), several as the zip a push builds, in its order:
  /// files by name (two of one name both count), folders as `<folder>/<path>`,
  /// then the metadata; each file read as a stream.
  Future<String?> _rommHashOfFiles(
      SaveStrategy strategy, Game game, String romPath, Map<io.File, io.File?> filesMap) async {
    final keys = filesMap.keys.toList();
    if (keys.length == 1 && !await io.FileSystemEntity.isDirectory(keys.single.path)) {
      return rommHashOfSaveFile(keys.single);
    }
    final files = await bundleFileDigests(keys);
    final meta = await _bundleMetadata(strategy, game, romPath, filesMap);
    files.add(('freegosy_sync.txt', md5.convert(utf8.encode(meta)).toString()));
    return rommHashOfDigests(files);
  }

  /// Tells RomM that this device has its [save] (an item of RomM's save list)
  /// without downloading it: the save on this PC is the same bytes. Like a
  /// download, this updates RomM's device sync, so this device's next upload
  /// isn't refused as made from an older save. Does nothing without a device
  /// id (RomM before device sync); never throws.
  Future<void> confirmRommCopy(Map<String, dynamic> save) async {
    final id = save['id'];
    final deviceId = _getDeviceId();
    if (id is! int || deviceId == null || deviceId.isEmpty) return;
    if (!await _rommService.confirmSaveDownloaded(id, deviceId: deviceId)) {
      debugPrint('[SaveSync] RomM wasn\'t told this device has save $id');
    }
  }

  /// Whether a restore left [strategy]'s save as it was ([before] is its
  /// fingerprint then): the strategy kept nothing of the download, so the
  /// pull counts as not done (no RomM id, no synced mark).
  Future<bool> _restoredNothing(SaveStrategy strategy, Game game, String romPath, String? before) async {
    if (before == null) return false;
    final after = await _fingerprintOf(strategy, game, romPath, 'saves');
    if (after != before) return false;
    debugPrint('[SaveSync] [pull] The save on this PC is unchanged — nothing was pulled');
    return true;
  }

  /// Whether RomM's [save] is the save already on this PC: its content_hash
  /// is the RomM hash of [strategy]'s save (as a push of either sync mode
  /// would upload it). Then a pull has nothing to do, and the save is
  /// recorded as RomM's copy of this PC's. False when RomM sent no hash.
  Future<bool> _alreadyHave(SaveStrategy strategy, Game game, String romPath, Map<String, dynamic> save) async {
    final remote = save['content_hash']?.toString();
    if (remote == null || remote.isEmpty) return false;
    if (!await _haveRommSave(strategy, game, romPath, save, remote)) return false;
    debugPrint('[SaveSync] [pull] RomM already has the save on this PC (same content_hash) — nothing to download');
    await confirmRommCopy(save);
    return true;
  }

  /// Whether the save on this PC is RomM's [save], whose RomM hash is
  /// [hash], as a push in either sync mode would upload it. If so it is
  /// recorded as RomM's: the synced fingerprint of every mode that matches
  /// (an unchanged session then uploads nothing, whichever mode it uses) and
  /// RomM's id for it.
  Future<bool> _haveRommSave(
      SaveStrategy strategy, Game game, String romPath, Map<String, dynamic> save, String? hash) async {
    if (hash == null) return false;
    var matched = false;
    for (final mode in const ['saves', 'both']) {
      if (await _rommHashOf(strategy, game, romPath, mode) != hash) continue;
      matched = true;
      final fingerprint = await _fingerprintOf(strategy, game, romPath, mode);
      if (fingerprint != null && fingerprint != 'none') {
        await _prefs.setString(_syncedKey(game.id, strategy.strategyId, mode), fingerprint);
      }
    }
    if (matched) await _recordSyncedRommId(game, strategy, save['id']);
    return matched;
  }

  /// The `freegosy_sync.txt` of a bundle: the content hash of [filesMap]
  /// (see saveContentHash) and, for a Windows game, where its saves go
  /// (`savePath` with environment folders as placeholders). No times: an
  /// unchanged save gives the same bundle, and so the same RomM content_hash.
  Future<String> _bundleMetadata(SaveStrategy strategy, Game game, String romPath, Map<io.File, io.File?> filesMap) async {
    final meta = <String, String>{'contentHash': await saveContentHash(filesMap)};
    if (strategy.strategyId == 'windows') {
      final saveAbsolutePath = await strategy.getSaveDir(game, romPath) ?? '';
      final winLocalAbsolutepath = <String, String>{
        "['APPDATA']": PlatformInfo.current.environment['APPDATA'] ?? '',
        "['LOCALAPPDATA']": PlatformInfo.current.environment['LOCALAPPDATA'] ?? '',
        "['USERPROFILE']": PlatformInfo.current.environment['USERPROFILE'] ?? '',
        "['PROGRAMDATA']": PlatformInfo.current.environment['PROGRAMDATA'] ?? '',
        "['PUBLIC']": PlatformInfo.current.environment['PUBLIC'] ?? '',
        "[GAMEDIR]": romPath,
      };
      var envPath = '';
      for (final entry in winLocalAbsolutepath.entries) {
        if (saveAbsolutePath.contains(entry.value)) {
          envPath = saveAbsolutePath.replaceFirst(entry.value, entry.key);
          break;
        }
      }
      meta['savePath'] = envPath;
    }
    return jsonEncode(meta);
  }

  /// Reads the `contentHash` field out of a downloaded bundle's
  /// `freegosy_sync.txt`, if [bytes] is a zip and that entry/field exists.
  /// Returns null for anything else (not a zip, no metadata entry, or a
  /// legacy timeStamp-only metadata format) so callers can fall through to
  /// an unconditional restore.
  String? _readBundleContentHash(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive) {
        if (!entry.isFile || p.basename(entry.name) != 'freegosy_sync.txt') continue;
        final meta = jsonDecode(utf8.decode(entry.content as List<int>)) as Map<String, dynamic>;
        return meta['contentHash'] as String?;
      }
    } catch (_) {}
    return null;
  }

  String _pullKey(String gameId) =>
      'last_pull_$gameId';

  DateTime? _getLastPullTime(String gameId) {
    final stored = _prefs.getString(_pullKey(gameId));
    if (stored == null) return null;
    return DateTime.tryParse(stored);
  }

  Future<void> _setLastPullTime(String gameId) async {
    await _prefs.setString(
      _pullKey(gameId),
      DateTime.now().toIso8601String(),
    );
  }

  // ---------------------------------------------------------------------------
  // Public entry points — version-aware routing
  // ---------------------------------------------------------------------------

  /// Uploads local save files for [game] to RomM.
  ///
  /// Routes to [_devicePushSaves] on RomM 4.9+ or [_legacyPushSaves] on older.
  ///
  /// [emulatorId] should be the emulator that actually launched the game
  /// this session (e.g. from the per-game emulator picker), if known. When
  /// omitted, the strategy falls back to the platform's globally-configured
  /// preferred emulator, which may differ from what was actually used
  /// (issue #79).
  Future<bool> pushSaves(Game game, String romPath,
          {DateTime? sessionStart, String syncMode = 'both', bool force = false, String? coreOverride, String? emulatorId}) =>
      _lock.run(() => _doing("Uploading ${game.displayName}'s save", () => _pushSavesUnlocked(game, romPath,
          sessionStart: sessionStart, syncMode: syncMode, force: force, coreOverride: coreOverride, emulatorId: emulatorId)));

  Future<bool> _pushSavesUnlocked(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both', bool force = false, String? coreOverride, String? emulatorId}) async {
    debugPrint('[SaveSync] ─── PUSH START ─── game="${game.displayName}" slug=${game.platformSlug}');
    debugPrint('[SaveSync]   romPath: $romPath');
    debugPrint('[SaveSync]   syncMode=$syncMode  force=$force  coreOverride=$coreOverride  emulatorId=$emulatorId  sessionStart=$sessionStart');
    await _throwIfSyncBlocked(game, romPath, emulatorId: emulatorId);
    final caps = await _rommService.fetchCapabilities();
    final useDevice = caps.hasDeviceSaveSync;
    debugPrint('[SaveSync]   RomM version: ${useDevice ? "4.9+ (device sync)" : "legacy (<4.9)"}');
    if (useDevice) {
      return _devicePushSaves(game, romPath,
          sessionStart: sessionStart, syncMode: syncMode, force: force, coreOverride: coreOverride, emulatorId: emulatorId);
    }
    return _legacyPushSaves(game, romPath,
        sessionStart: sessionStart, syncMode: syncMode, force: force, coreOverride: coreOverride, emulatorId: emulatorId);
  }

  /// In-memory cache of the last pull-check timestamp per game.
  /// Prevents hitting RomM on every rapid re-launch. Without this,
  /// each game launch makes 2 HTTP requests (list saves + download)
  /// which adds 5-15s of latency. The cooldown means re-launching the
  /// same game within 60s skips the network check entirely.
  final Map<String, DateTime> _lastPullCheck = {};
  static const _pullCheckCooldown = Duration(seconds: 60);

  /// Downloads and restores a save for [game] from RomM.
  ///
  /// Routes to [_devicePullSave] on RomM 4.9+ or [_legacyPullSave] on older.
  /// Skips network requests if the last check was within [_pullCheckCooldown].
  /// This is called before emulator launch — the save is usually already on
  /// disk from the last session, so the pull is non-blocking (fire-and-forget).
  Future<bool> pullSave(Game game, String romPath, {Map<String, dynamic>? saveData, String? coreOverride, String? emulatorId}) =>
      _lock.run(() => _doing("Downloading ${game.displayName}'s save",
          () => _pullSaveUnlocked(game, romPath, saveData: saveData, coreOverride: coreOverride, emulatorId: emulatorId)));

  Future<bool> _pullSaveUnlocked(Game game, String romPath, {Map<String, dynamic>? saveData, String? coreOverride, String? emulatorId}) async {
    final now = DateTime.now();
    final lastCheck = _lastPullCheck[game.id];
    if (saveData == null && lastCheck != null && now.difference(lastCheck) < _pullCheckCooldown) {
      debugPrint('[SaveSync] ─── PULL SKIP ─── "${game.displayName}" checked ${now.difference(lastCheck).inSeconds}s ago (cooldown)');
      return false;
    }
    _lastPullCheck[game.id] = now;

    debugPrint('[SaveSync] ─── PULL START ─── game="${game.displayName}" slug=${game.platformSlug}');
    debugPrint('[SaveSync]   romPath: $romPath  coreOverride=$coreOverride  emulatorId=$emulatorId  saveData=${saveData != null ? "manual" : "auto"}');
    await _throwIfSyncBlocked(game, romPath, emulatorId: emulatorId);
    final caps = await _rommService.fetchCapabilities();
    final useDevice = caps.hasDeviceSaveSync;
    debugPrint('[SaveSync]   RomM version: ${useDevice ? "4.9+ (device sync)" : "legacy (<4.9)"}');
    if (useDevice) {
      return _devicePullSave(game, romPath, saveData: saveData, coreOverride: coreOverride, emulatorId: emulatorId);
    }
    return _legacyPullSave(game, romPath, saveData: saveData, coreOverride: coreOverride, emulatorId: emulatorId);
  }

  // ---------------------------------------------------------------------------
  // Helpers shared by both paths
  // ---------------------------------------------------------------------------

  /// Throws [SaveSyncNotPossibleException] when [game]'s save strategy says
  /// the emulator is set up so its saves can't be synced (see
  /// [SaveStrategy.saveSyncBlockedReason]).
  Future<void> _throwIfSyncBlocked(Game game, String romPath, {String? emulatorId}) async {
    final reason =
        await getStrategyForGame(game, emulatorId: emulatorId)?.saveSyncBlockedReason(game, romPath);
    if (reason == null) return;
    debugPrint('[SaveSync] not syncing "${game.displayName}": $reason');
    throw SaveSyncBlockedException(reason);
  }

  String? _getDeviceId() => _prefs.getString('romm_device_id');

  /// The emulator a save is tagged with on RomM: RetroArch's core (e.g.
  /// `pcsx_rearmed`, as RomM's in-browser player and Argosy name it), else
  /// the emulator's id. RomM's player lists saves of every emulator but loads
  /// save states only into their own core; the tag says which emulator made
  /// a save, and on a pull which format it is in (see save/formats).
  String _saveEmulatorTag(SaveStrategy strategy, Game game, String? emulatorId) {
    if (strategy is RetroArchSaveStrategy) {
      final core = strategy.coreIdFor(game);
      if (core != null) return core;
    }
    return emulatorId ?? strategy.strategyId;
  }

  /// [bytes] uncompressed when RetroArch wrote them as RZIP ("SaveRAM
  /// compression"), which RetroArch reads either way and nothing else reads
  /// compressed; else, or when malformed, as they came.
  Future<Uint8List> _unrzipDownload(Uint8List bytes, String filename) async {
    if (!Rzip.isRzip(bytes)) return bytes;
    try {
      final raw = await Rzip.unpack(bytes, zstd: _zstd);
      debugPrint('[SaveSync] [pull] $filename is RZIP-compressed — unpacked ${bytes.length} → ${raw.length} bytes');
      return raw;
    } catch (e) {
      // Malformed, or the zstandard library failed: RetroArch reads its own
      // RZIP files anyway.
      debugPrint('[SaveSync] [pull] $filename looks RZIP-compressed but can\'t be unpacked ($e) — restoring it as it is');
      return bytes;
    }
  }

  /// [filesMap] with every RZIP-compressed file replaced by an uncompressed
  /// copy of the same name and time, so RomM gets the raw save that every
  /// emulator and client reads, and hashes compare contents. The copies go
  /// in a per-game temporary folder, like DuckStation's uploads.
  Future<Map<io.File, io.File?>> _unrzipFiles(Game game, Map<io.File, io.File?> filesMap) async {
    final result = <io.File, io.File?>{};
    for (final entry in filesMap.entries) {
      final file = entry.key;
      if (!await io.FileSystemEntity.isFile(file.path)) {
        result[file] = entry.value;
        continue;
      }
      final bytes = await file.readAsBytes();
      if (!Rzip.isRzip(bytes)) {
        result[file] = entry.value;
        continue;
      }
      try {
        final raw = await Rzip.unpack(bytes, zstd: _zstd);
        final dir = io.Directory(p.join(io.Directory.systemTemp.path, 'freegosy_unrzip',
            game.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')));
        await dir.create(recursive: true);
        final copy = io.File(p.join(dir.path, p.basename(file.path)));
        await copy.writeAsBytes(raw);
        await copy.setLastModified(await file.lastModified());
        debugPrint('[SaveSync] ${p.basename(file.path)} is RZIP-compressed — using it unpacked (${raw.length} bytes)');
        result[copy] = entry.value;
      } catch (e) {
        debugPrint('[SaveSync] ${p.basename(file.path)} looks RZIP-compressed but can\'t be unpacked ($e) — using it as it is');
        result[file] = entry.value;
      }
    }
    return result;
  }

  /// Restores a downloaded save, converted first to the format the local
  /// emulator reads (save/formats) when it came from another emulator.
  /// [sourceTag] is the save's `emulator` on RomM.
  Future<bool> _restoreDownloaded(SaveStrategy strategy, Game game, String romPath, Uint8List bytes,
      String filename, {String? sourceTag, String? emulatorId}) async {
    final platformSlug = game.platformSlug ?? '';
    final convertible = saveSystemFor(platformSlug) != null;
    // A zip holding one save file (as older uploads were) is restored as that
    // file, converted when it's in another emulator's format.
    final source = convertible && filename.toLowerCase().endsWith('.zip') ? _singleSaveInZip(bytes) : null;
    // Still RZIP (it couldn't be unpacked): its bytes are no format's, even
    // when big enough to pass for one.
    final asItCame = [source ?? SaveBlob(filename, bytes)];
    final conversion = !convertible || Rzip.isRzip(bytes)
        ? const SaveAsIs()
        : convertSave(
            platformSlug: platformSlug,
            files: asItCame,
            sourceTag: sourceTag,
            targetTag: _saveEmulatorTag(strategy, game, emulatorId),
            stem: strategy.getRomStem(game),
            existing: await _localSaveBlobs(strategy, game, romPath),
          );
    // A pull restores what it can't convert as it came, as it always did.
    for (final blob in conversion is SaveConverted ? conversion.files : asItCame) {
      if (!await strategy.restoreSave(game, romPath, blob.bytes, blob.name)) return false;
    }
    return true;
  }

  /// The one save file in [zipBytes], leaving out Freegosy's sync metadata,
  /// screenshots and save states; null when there are none, several, or the
  /// zip can't be read.
  static SaveBlob? _singleSaveInZip(Uint8List zipBytes) {
    try {
      final saves = [
        for (final entry in ZipDecoder().decodeBytes(zipBytes))
          if (entry.isFile &&
              p.basename(entry.name) != 'freegosy_sync.txt' &&
              !const {'.png', '.jpg', '.jpeg'}.contains(p.extension(entry.name).toLowerCase()) &&
              !p.basename(entry.name).toLowerCase().contains('.state'))
            entry,
      ];
      if (saves.length != 1) return null;
      return SaveBlob(p.basename(saves.single.name), Uint8List.fromList(saves.single.content as List<int>));
    } catch (_) {
      return null;
    }
  }

  /// The game's save files on this machine, for a conversion that keeps what
  /// the pulled save doesn't carry (a memory card's other games' saves). Folders
  /// and files over 1 MB are left out; unreadable saves leave the list empty.
  Future<List<SaveBlob>> _localSaveBlobs(SaveStrategy strategy, Game game, String romPath) async {
    final blobs = <SaveBlob>[];
    try {
      for (final file in await strategy.getSaveFiles(game, romPath, syncMode: 'saves')) {
        if (!await io.FileSystemEntity.isFile(file.path) || await file.length() > 1024 * 1024) continue;
        final name = p.basename(file.path);
        blobs.add(SaveBlob(name, await _unrzipDownload(await file.readAsBytes(), name)));
      }
    } catch (e) {
      debugPrint('[SaveSync] [pull] local saves unreadable ($e) — converting without them');
      return [];
    }
    return blobs;
  }

  /// Downloads the RomM save [save] (an item of RommService.getSavesList)
  /// and puts it in place for [emulatorId], converted when it is in another
  /// emulator's format. Unlike pullSave it never skips: the user chose it.
  Future<void> restoreChosenSave(Game game, String romPath, Map<String, dynamic> save,
          {required String emulatorId, String? coreOverride}) =>
      _lock.run(() => _doing("Downloading ${game.displayName}'s save",
          () => _restoreChosenSaveUnlocked(game, romPath, save, emulatorId: emulatorId, coreOverride: coreOverride)));

  Future<void> _restoreChosenSaveUnlocked(Game game, String romPath, Map<String, dynamic> save,
      {required String emulatorId, String? coreOverride}) async {
    final strategy = _saveStrategyFor(game, emulatorId, coreOverride: coreOverride);
    if (strategy == null) throw SaveChoiceException("$emulatorId saves can't be set up by Freegosy.");
    final url = save['download_path'] as String? ?? save['url'] as String?;
    final filename = save['file_name']?.toString() ?? url?.split('/').last ?? 'save';
    if (url == null) throw SaveChoiceException("RomM didn't say where to download $filename.");
    final downloaded = await _rommService.downloadSave(url, deviceId: _getDeviceId());
    if (downloaded == null) throw SaveChoiceException("$filename couldn't be downloaded from RomM.");
    final bytes = await _unrzipDownload(downloaded, filename);
    final name = _adjustFilenameForFormat(bytes, normalizeSaveFilename(filename));
    final ok = await _restoreDownloaded(strategy, game, romPath, bytes, name,
        sourceTag: save['emulator']?.toString(), emulatorId: emulatorId);
    if (!ok) throw SaveChoiceException("$filename couldn't be put in place for $emulatorId.");
    await _setLastPullTime(game.id);
    await _recordSyncedRommId(game, strategy, save['id']);
  }

  /// Converts the save [fromEmulatorId] keeps for [game] on this machine
  /// into [emulatorId]'s format and puts it in place.
  Future<void> convertLocalSave(Game game, String romPath,
          {required String fromEmulatorId, String? fromTag, required String emulatorId, String? coreOverride}) =>
      _lock.run(() => _convertLocalSaveUnlocked(game, romPath,
          fromEmulatorId: fromEmulatorId, fromTag: fromTag, emulatorId: emulatorId, coreOverride: coreOverride));

  Future<void> _convertLocalSaveUnlocked(Game game, String romPath,
      {required String fromEmulatorId, String? fromTag, required String emulatorId, String? coreOverride}) async {
    // Read the source with its own setup first: for one emulator both are
    // the same shared strategy.
    final from = _saveStrategyFor(game, fromEmulatorId, coreOverride: fromEmulatorId == 'retroarch' ? fromTag : null);
    if (from == null) throw SaveChoiceException("This save can't be moved to $emulatorId.");
    final files = await _localSaveBlobs(from, game, romPath);
    if (files.isEmpty) throw SaveChoiceException('The $fromEmulatorId save is gone.');
    final to = _saveStrategyFor(game, emulatorId, coreOverride: coreOverride);
    if (to == null) throw SaveChoiceException("This save can't be moved to $emulatorId.");
    // Another emulator's save moves only within a save system: its formats
    // say how, or that it is the same bytes (raw systems).
    if (saveSystemFor(game.platformSlug ?? '') == null) {
      throw SaveChoiceException("$fromEmulatorId saves can't be moved to $emulatorId.");
    }
    final conversion = convertSave(
      platformSlug: game.platformSlug ?? '',
      files: files,
      sourceTag: fromTag ?? fromEmulatorId,
      targetTag: _saveEmulatorTag(to, game, emulatorId),
      stem: to.getRomStem(game),
      existing: await _localSaveBlobs(to, game, romPath),
    );
    final out = switch (conversion) {
      SaveConverted(:final files) => files,
      SaveAsIs() => files, // the same bytes the target reads
      SaveNotConvertible(:final reason) =>
        throw SaveChoiceException("The $fromEmulatorId save can't be used by $emulatorId: $reason."),
    };
    for (final blob in out) {
      if (!await to.restoreSave(game, romPath, blob.bytes, blob.name)) {
        throw SaveChoiceException("The converted save couldn't be written for $emulatorId.");
      }
    }
  }

  /// A hash of [emulatorId]'s save files for [game] that changes only when
  /// their contents do: `'none'` when there are none, null when they can't
  /// be read. [syncMode] as for pushSaves, so it covers what a push uploads.
  Future<String?> saveFingerprint(Game game, String romPath,
          {required String emulatorId, String syncMode = 'saves', String? coreOverride}) =>
      _lock.run(() => _saveFingerprintUnlocked(game, romPath, emulatorId: emulatorId, syncMode: syncMode, coreOverride: coreOverride));

  Future<String?> _saveFingerprintUnlocked(Game game, String romPath,
      {required String emulatorId, String syncMode = 'saves', String? coreOverride}) async {
    final strategy = _saveStrategyFor(game, emulatorId, coreOverride: coreOverride);
    if (strategy == null) return null;
    return _fingerprintOf(strategy, game, romPath, syncMode);
  }

  /// saveFingerprint for a [strategy] already set up for [game].
  Future<String?> _fingerprintOf(SaveStrategy strategy, Game game, String romPath, String syncMode) async {
    try {
      final files = await _unrzipFiles(game, await strategy.getSaveFilesWithScreenshots(game, romPath, syncMode: syncMode));
      if (files.isEmpty) return 'none';
      return await saveContentHash(files);
    } catch (e) {
      debugPrint('[SaveSync] fingerprint of ${game.displayName} not taken: $e');
      return null;
    }
  }

  String _syncedKey(String gameId, String strategyId, String syncMode) => 'synced_fp_${gameId}_${strategyId}_$syncMode';

  String _syncedIdKey(String gameId, String strategyId) => 'synced_romm_id_${gameId}_$strategyId';

  /// Forgets that RomM had [game]'s saves (a RomM save of it was deleted):
  /// the next session uploads again, even an unchanged save, and the next
  /// pull doesn't count the local save as RomM's.
  Future<void> forgetSynced(Game game) async {
    // Also the uploaded-file hashes, or push would skip the unchanged save.
    final prefixes = ['synced_fp_${game.id}_', 'synced_romm_id_${game.id}_', 'last_hash_${game.id}_'];
    for (final key in _prefs.getKeys().where((k) => prefixes.any(k.startsWith)).toList()) {
      await _prefs.remove(key);
    }
  }

  /// Records that RomM's save [rommId] holds what [strategy] has for [game]
  /// (it was just uploaded or put in place).
  Future<void> _recordSyncedRommId(Game game, SaveStrategy strategy, Object? rommId) async {
    if (rommId == null) return;
    await _prefs.setString(_syncedIdKey(game.id, strategy.strategyId), rommId.toString());
  }

  /// The id of the RomM save that holds exactly [emulatorId]'s current save
  /// for [game], as this PC last synced it; null when the save changed since
  /// or was never synced.
  Future<String?> rommCopyOfLocal(Game game, String romPath, {required String emulatorId, String? coreOverride}) =>
      _lock.run(() async {
        final strategy = _saveStrategyFor(game, emulatorId, coreOverride: coreOverride);
        if (strategy == null) return null;
        final id = _prefs.getString(_syncedIdKey(game.id, strategy.strategyId));
        if (id == null) return null;
        for (final mode in const ['saves', 'both']) {
          final synced = _prefs.getString(_syncedKey(game.id, strategy.strategyId, mode));
          if (synced != null && synced == await _fingerprintOf(strategy, game, romPath, mode)) return id;
        }
        return null;
      });

  /// Records that RomM has [emulatorId]'s current save for [game] (it was
  /// just pulled, restored from RomM or pushed), as seen with [syncMode].
  Future<void> markSaveSynced(Game game, String romPath,
          {required String emulatorId, required String syncMode, String? coreOverride}) =>
      _lock.run(() => _markSaveSyncedUnlocked(game, romPath, emulatorId: emulatorId, syncMode: syncMode, coreOverride: coreOverride));

  Future<void> _markSaveSyncedUnlocked(Game game, String romPath,
      {required String emulatorId, required String syncMode, String? coreOverride}) async {
    final strategy = _saveStrategyFor(game, emulatorId, coreOverride: coreOverride);
    if (strategy == null) return;
    final fp = await _fingerprintOf(strategy, game, romPath, syncMode);
    if (fp == null || fp == 'none') return;
    await _prefs.setString(_syncedKey(game.id, strategy.strategyId, syncMode), fp);
  }

  /// Whether [emulatorId]'s current save for [game] is the content RomM has,
  /// as far as this device knows (see markSaveSynced), seen with [syncMode].
  Future<bool> saveIsSynced(Game game, String romPath,
          {required String emulatorId, required String syncMode, String? coreOverride}) =>
      _lock.run(() => _saveIsSyncedUnlocked(game, romPath, emulatorId: emulatorId, syncMode: syncMode, coreOverride: coreOverride));

  Future<bool> _saveIsSyncedUnlocked(Game game, String romPath,
      {required String emulatorId, required String syncMode, String? coreOverride}) async {
    final strategy = _saveStrategyFor(game, emulatorId, coreOverride: coreOverride);
    if (strategy == null) return false;
    final synced = _prefs.getString(_syncedKey(game.id, strategy.strategyId, syncMode));
    if (synced == null) return false;
    return await _fingerprintOf(strategy, game, romPath, syncMode) == synced;
  }

  /// The newest modification time among [entries], looking inside folders
  /// (folder saves: PPSSPP SAVEDATA, PCSX2 folder cards); null when none.
  @visibleForTesting
  static Future<DateTime?> newestModified(Iterable<io.FileSystemEntity> entries) async {
    DateTime? newest;
    Future<void> see(io.File f) async {
      final t = await f.lastModified();
      if (newest == null || t.isAfter(newest!)) newest = t;
    }

    for (final entry in entries) {
      if (await io.FileSystemEntity.isDirectory(entry.path)) {
        await for (final child in io.Directory(entry.path).list(recursive: true)) {
          if (child is io.File) await see(child);
        }
      } else if (await io.File(entry.path).exists()) {
        await see(io.File(entry.path));
      }
    }
    return newest;
  }

  /// Whether the newest local save file of [strategy] for [game] is newer
  /// than RomM's [save] — an automatic pull then leaves it, and the push
  /// after the next session uploads it. False when either time is unknown.
  ///
  /// Not used for a file other games share (a memory card): its time says
  /// nothing about this game. A save with the content RomM already has
  /// (markSaveSynced) is not newer either, whatever its time: emulators
  /// rewrite unchanged saves on exit.
  Future<bool> _localSaveIsNewer(SaveStrategy strategy, Game game, String romPath, Map<String, dynamic> save) async {
    final cloud = DateTime.tryParse(save['updated_at']?.toString() ?? '') ??
        DateTime.tryParse(save['created_at']?.toString() ?? '');
    if (cloud == null) return false;
    try {
      if (await strategy.pullMustFinishBeforeLaunch(game, romPath)) return false;
      final newest = await newestModified(await strategy.getSaveFiles(game, romPath, syncMode: 'saves'));
      if (newest == null || !newest.isAfter(cloud)) return false;
      for (final mode in const ['saves', 'both']) {
        final synced = _prefs.getString(_syncedKey(game.id, strategy.strategyId, mode));
        if (synced != null && synced == await _fingerprintOf(strategy, game, romPath, mode)) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _applyStrategyMappings(SaveStrategy strategy, Game game, {String? coreOverride}) {
    if (strategy is RetroArchSaveStrategy) {
      strategy.setLaunchCoreOverride(coreOverride);
    } else if (strategy is EdenSaveStrategy) {
      strategy.setManualMapping(getMappedFolder(game.id));
      strategy.setActiveProfileOverride(getActiveProfile());
    } else if (strategy is RyujinxSaveStrategy) {
      strategy.setManualMapping(getMappedFolder(game.id));
      strategy.setActiveProfileOverride(getActiveProfile());
    } else if (strategy is AzaharSaveStrategy) {
      strategy.setManualMapping(getMappedFolder(game.id));
    }
  }

  /// Filters the files map to a single primary save when the strategy does not
  /// support ZIP bundles.
  ///
  /// Directories are always passed through — they represent whole save folders
  /// (e.g. Dolphin Wii title dirs, PPSSPP SAVEDATA) that the bundling path in
  /// _devicePushSaves / _legacyPushSaves already handles correctly by zipping
  /// them. Dropping them here was the root cause of Wii saves never uploading.
  Map<io.File, io.File?> _filterFilesMap(
      SaveStrategy strategy, Map<io.File, io.File?> filesMap) {
    if (strategy.shouldZip) {
      debugPrint('[SaveSync]   Filter: strategy supports ZIP, passing all ${filesMap.length} file(s) through');
      return filesMap;
    }
    final filtered = <io.File, io.File?>{};
    for (final entry in filesMap.entries) {
      // Always pass directories through — callers zip them.
      if (io.FileSystemEntity.isDirectorySync(entry.key.path)) {
        filtered[entry.key] = entry.value;
        return filtered;
      }
      final pathLower = entry.key.path.toLowerCase();
      // Battery-backed save files — must match RetroArchSaveStrategy._saveExtensions
      if (pathLower.endsWith('.srm') ||
          pathLower.endsWith('.sav') ||
          pathLower.endsWith('.gci') ||
          pathLower.endsWith('.sra') ||
          pathLower.endsWith('.eep') ||
          pathLower.endsWith('.fla') ||
          pathLower.endsWith('.mpk') ||
          pathLower.endsWith('.mcd')) {
        filtered[entry.key] = entry.value;
        break;
      }
    }
    if (filtered.isEmpty) {
      // Last resort: take the first file entry.
      debugPrint('[SaveSync]   Filter: no .srm/.sav/.gci/etc. found, taking first entry as fallback');
      for (final entry in filesMap.entries) {
        filtered[entry.key] = entry.value;
        break;
      }
    }
    return filtered;
  }

  // ---------------------------------------------------------------------------
  // RomM 4.9+ device-based sync
  // ---------------------------------------------------------------------------

  Future<bool> _devicePushSaves(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both', bool force = false, String? coreOverride, String? emulatorId}) async {
    try {
      final strategy = getStrategyForGame(game, emulatorId: emulatorId);
      if (strategy == null) {
        debugPrint('[SaveSync] [push] No save strategy for slug="${game.platformSlug}" — game "${game.displayName}" not supported');
        return false;
      }
      debugPrint('[SaveSync] [push] Strategy: ${strategy.strategyId}  game="${game.displayName}"');
      _applyStrategyMappings(strategy, game, coreOverride: coreOverride);

      var filesMap = await strategy.getSaveFilesWithScreenshots(
        game, romPath,
        sessionStart: sessionStart,
        syncMode: syncMode,
      );
      debugPrint('[SaveSync] [push] Found ${filesMap.length} save file(s) from strategy');
      if (filesMap.isEmpty) {
        debugPrint('[SaveSync] [push] No save files found on disk — nothing to upload');
        return false;
      }
      // Log what was found (paths + sizes)
      for (final entry in filesMap.entries) {
        final f = entry.key;
        final isDir = io.FileSystemEntity.isDirectorySync(f.path);
        final exists = io.FileSystemEntity.isFileSync(f.path);
        final size = exists && !isDir ? io.File(f.path).lengthSync() : -1;
        debugPrint('[SaveSync] [push]   → ${f.path}  (${isDir ? "dir" : "$size bytes"})');
      }
      filesMap = _filterFilesMap(strategy, filesMap);
      debugPrint('[SaveSync] [push] After filter: ${filesMap.length} file(s) to upload');
      if (filesMap.isEmpty) {
        debugPrint('[SaveSync] [push] All files filtered out — nothing to upload');
        return false;
      }
      filesMap = await _unrzipFiles(game, filesMap);

      final displayStem =
          game.displayName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final tempDir = await _directoryService.getEmulatorDirectory('temp');
      if (!await io.Directory(tempDir).exists()) {
        await io.Directory(tempDir).create(recursive: true);
      }

      io.File? finalUploadFile;
      io.File? finalScreenshotFile;
      String uploadFilename;
      bool isBundle = false;

      if (filesMap.length == 1 &&
          !await io.FileSystemEntity.isDirectory(filesMap.keys.first.path)) {
        final entry = filesMap.entries.first;
        finalUploadFile = entry.key;
        finalScreenshotFile = entry.value;
        uploadFilename = p.basename(finalUploadFile.path);
        debugPrint('[SaveSync] [push] Mode: single file → $uploadFilename');
      } else {
        isBundle = true;
        debugPrint('[SyncService] [4.9] _devicePushSaves: mode=bundle');
        final bundleToken = DateTime.now().millisecondsSinceEpoch;
        final bundleZipPath = p.join(tempDir, '$displayStem.bundle.$bundleToken.zip');
        final encoder = ZipFileEncoder();
        encoder.create(bundleZipPath);
        // Scoped to this call's bundleToken — a shared literal filename here
        // would race with any other concurrent push/pull writing/deleting
        // the same path in the same temp directory.
        final metaFile = io.File(p.join(tempDir, 'freegosy_sync.$bundleToken.txt'));

        await metaFile.writeAsString(await _bundleMetadata(strategy, game, romPath, filesMap));
        await encoder.addFile(metaFile, 'freegosy_sync.txt');
        await metaFile.delete();
        for (final entry in filesMap.entries) {
          final file = entry.key;
          if (await io.FileSystemEntity.isDirectory(file.path)) {
            await encoder.addDirectory(io.Directory(file.path),
                includeDirName: true);
          } else {
            await encoder.addFile(file, p.basename(file.path));
          }
        }
        encoder.close();
        finalUploadFile = io.File(bundleZipPath);
        uploadFilename = '$displayStem.zip';
        finalScreenshotFile =
            filesMap.values.firstWhere((s) => s != null, orElse: () => null);
      }

      // Reject empty/blank saves to prevent overwriting legitimate cloud saves.
      final fileLen = await finalUploadFile.length();
      if (fileLen < minValidSaveSizeBytes) {
        debugPrint('[SaveSync] [push] Rejected: $displayStem is only $fileLen bytes (min=$minValidSaveSizeBytes)');
        if (isBundle && await finalUploadFile.exists()) {
          await finalUploadFile.delete();
        }
        return false;
      }

      // RomM's hash of the upload (a zip by its contents): an unchanged save
      // keeps it even when its emulator rewrote the files.
      final String localHash =
          await rommHashOfSaveFile(finalUploadFile) ?? await _hashFile(finalUploadFile);
      final String? storedHash = _getStoredHash(game.id, uploadFilename);

      if (!force && storedHash != null && localHash == storedHash) {
        debugPrint('[SaveSync] [push] Hash unchanged — skipping upload (already synced)');
        if (isBundle && await finalUploadFile.exists()) {
          await finalUploadFile.delete();
        }
        return true;
      }

      final deviceId = _getDeviceId();
      final result = await _rommService.uploadSave(
        game.id,
        finalUploadFile,
        emulator: _saveEmulatorTag(strategy, game, emulatorId),
        deviceId: deviceId,
        slot: 'freegosy',
        autocleanup: true,
        autocleanupLimit: 5,
        overwrite: force,
        screenshotFile: finalScreenshotFile,
        overrideFilename: uploadFilename,
      );

      if (!result.ok && result.conflict != null) {
        debugPrint('[SaveSync] [push] Conflict detected — cloud save is newer');
        final cloudTimeStr = result.conflict!['current_save_time']?.toString();
        final cloudTime =
            cloudTimeStr != null ? DateTime.tryParse(cloudTimeStr) : null;
        DateTime? localTime;
        for (final file in filesMap.keys) {
          final mtime = await file.lastModified();
          if (localTime == null || mtime.isAfter(localTime)) localTime = mtime;
        }
        if (isBundle && await finalUploadFile.exists()) {
          await finalUploadFile.delete();
        }
        throw SaveConflictException(
          game: game,
          localTime: localTime ?? DateTime.now(),
          cloudTime: cloudTime ?? DateTime.now(),
        );
      }

      if (result.ok) {
        await _storeHash(game.id, uploadFilename, localHash);
        await _recordSyncedRommId(game, strategy, result.saved?['id']);
        debugPrint('[SaveSync] [push] Upload OK — $uploadFilename ($fileLen bytes) saved to RomM');
      } else {
        debugPrint('[SaveSync] [push] Upload FAILED — server returned ok=false');
      }

      if (isBundle && await finalUploadFile.exists()) await finalUploadFile.delete();
      debugPrint('[SaveSync] ─── PUSH END ─── ok=${result.ok}');
      return result.ok;
    } on SaveConflictException {
      rethrow;
    } on SaveSyncNotPossibleException {
      rethrow;
    } catch (e) {
      debugPrint('[SaveSync] [push] ERROR: $e');
      return false;
    }
  }

  Future<bool> _devicePullSave(Game game, String romPath,
      {Map<String, dynamic>? saveData, String? coreOverride, String? emulatorId}) async {
    try {
      final strategy = getStrategyForGame(game, emulatorId: emulatorId);
      if (strategy == null) {
        debugPrint('[SaveSync] [pull] No save strategy for slug="${game.platformSlug}"');
        return false;
      }
      debugPrint('[SaveSync] [pull] Strategy: ${strategy.strategyId}');
      _applyStrategyMappings(strategy, game, coreOverride: coreOverride);

      final deviceId = _getDeviceId();
      debugPrint('[SaveSync] [pull] Fetching latest save from server (deviceId=${deviceId ?? "none"})...');
      final Map<String, dynamic>? save =
          saveData ?? await _rommService.getLatestSave(game.id, deviceId: deviceId);
      if (save == null) {
        debugPrint('[SaveSync] [pull] No save found on server — nothing to pull');
        return false;
      }

      // If server says we already have the current version, skip
      if (saveData == null && deviceId != null) {
        final syncs = save['device_syncs'] as List<dynamic>?;
        final mySync = syncs?.firstWhere(
          (d) => d['device_id'] == deviceId,
          orElse: () => null,
        );
        if (mySync != null && mySync['is_current'] == true) {
          debugPrint('[SaveSync] [pull] Already current on this device — skipping');
          return false;
        }
      }

      if (saveData == null && await _localSaveIsNewer(strategy, game, romPath, save)) {
        debugPrint('[SaveSync] [pull] The local save is newer than RomM\'s — keeping it');
        return false;
      }
      if (await _alreadyHave(strategy, game, romPath, save)) return false;

      final downloadUrl =
          save['download_path'] as String? ?? save['url'] as String?;
      if (downloadUrl == null) {
        debugPrint('[SaveSync] [pull] Save record found but no download URL');
        return false;
      }

      final filename =
          save['file_name'] as String? ?? downloadUrl.split('/').last;
      debugPrint('[SaveSync] [pull] Cloud save: $filename');

      // Skip save states — only sync battery-backed saves (.srm, .sav, .sra, etc.)
      final fnameLower = filename.toLowerCase();
      if (fnameLower.endsWith('.state') ||
          fnameLower.contains('.state.') ||
          fnameLower.endsWith('.state.auto') ||
          RegExp(r'\.state\d+$').hasMatch(fnameLower)) {
        debugPrint('[SaveSync] [pull] Skipping — latest cloud save is a state file ($filename)');
        return false;
      }

      final downloaded = await _rommService.downloadSave(downloadUrl, deviceId: deviceId);
      if (downloaded == null) {
        debugPrint('[SaveSync] [pull] Download failed');
        return false;
      }
      final bytes = await _unrzipDownload(downloaded, filename);

      final adjustedFilename = _adjustFilenameForFormat(bytes, normalizeSaveFilename(filename));
      debugPrint('[SaveSync] [pull] Downloaded ${bytes.length} bytes → restoring as "$adjustedFilename"');

      // Skip the restore entirely when the cloud bundle's freegosy_sync.txt
      // carries a contentHash (written by strategies that opt into it, e.g.
      // PCSX2 — see _devicePushSaves) that already matches what's on disk.
      // Generic to any strategy's metadata format: a legacy timeStamp-only
      // bundle has no contentHash key, so this simply falls through to an
      // unconditional restore exactly as before.
      if (adjustedFilename.toLowerCase().endsWith('.zip')) {
        final cloudContentHash = _readBundleContentHash(bytes);
        if (cloudContentHash != null) {
          final localFilesMap =
              await _unrzipFiles(game, await strategy.getSaveFilesWithScreenshots(game, romPath, syncMode: 'both'));
          if (localFilesMap.isNotEmpty) {
            final localContentHash = await saveContentHash(localFilesMap);
            if (localContentHash == cloudContentHash) {
              debugPrint('[SaveSync] [pull] Local save content already matches cloud — skipping restore');
              return false;
            }
          }
        }
      }

      if (SaveRestoreGuard.restoreTooLate) {
        debugPrint('[SaveSync] [pull] The launch went ahead without this pull — not restoring "$adjustedFilename"');
        return false;
      }
      // The download is the save already on this PC (RomM sent no hash, or
      // one that didn't match): nothing to write, and the save is RomM's.
      if (await _haveRommSave(strategy, game, romPath, save, rommHashOfUpload(bytes))) {
        debugPrint('[SaveSync] [pull] The downloaded save is the one on this PC — kept as it is');
        await _setLastPullTime(game.id);
        return true;
      }
      // A strategy can take a download and keep nothing of it (DuckStation and
      // a file that is no memory card): then nothing was pulled.
      final before = await _fingerprintOf(strategy, game, romPath, 'saves');
      final ok = await _restoreDownloaded(strategy, game, romPath, bytes, adjustedFilename,
          sourceTag: save['emulator']?.toString(), emulatorId: emulatorId);
      if (!ok) {
        debugPrint('[SaveSync] [pull] Strategy failed to restore save');
        throw Exception(
            'Strategy [${strategy.strategyId}] failed to restore save: $filename');
      }
      if (await _restoredNothing(strategy, game, romPath, before)) return false;
      await _recordSyncedRommId(game, strategy, save['id']);
      debugPrint('[SaveSync] ─── PULL END ─── restored OK');
      return ok;
    } on io.FileSystemException catch (e) {
      throw Exception('Disk Error: ${e.message} (Path: ${e.path})');
    } on DioException catch (e) {
      throw Exception('Network Error: ${e.message} (Status: ${e.response?.statusCode})');
    } catch (e) {
      if (e.toString().contains('Exception: ')) rethrow;
      throw Exception('Pull Failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Legacy sync (RomM < 4.9) — kept for backward compatibility
  // ---------------------------------------------------------------------------

  /// Legacy upload path for RomM versions prior to 4.9.
  /// Uses timestamp-based conflict detection and manual save pruning.
  Future<bool> _legacyPushSaves(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both', bool force = false, String? coreOverride, String? emulatorId}) async {
    try {
      final strategy = getStrategyForGame(game, emulatorId: emulatorId);
      if (strategy == null) {
        debugPrint('[SaveSync] [push] No save strategy for slug="${game.platformSlug}"');
        return false;
      }
      debugPrint('[SaveSync] [push] Strategy: ${strategy.strategyId}  (legacy path)');

      _applyStrategyMappings(strategy, game, coreOverride: coreOverride);

      var filesMap = await strategy.getSaveFilesWithScreenshots(
        game, romPath,
        sessionStart: sessionStart,
        syncMode: syncMode,
      );
      debugPrint('[SaveSync] [push] Found ${filesMap.length} save file(s)');
      for (final entry in filesMap.entries) {
        final f = entry.key;
        final isDir = io.FileSystemEntity.isDirectorySync(f.path);
        final exists = io.FileSystemEntity.isFileSync(f.path);
        final size = exists && !isDir ? io.File(f.path).lengthSync() : -1;
        debugPrint('[SaveSync] [push]   → ${f.path}  (${isDir ? "dir" : "$size bytes"})');
      }
      if (filesMap.isEmpty) {
        debugPrint('[SaveSync] [push] No save files found — nothing to upload');
        return false;
      }

      // If the strategy does not support zipping, filter filesMap to only keep the primary save file
      // (typically ending in .srm, .sav, or .gci) to ensure it is uploaded raw/unzipped.
      if (!strategy.shouldZip) {
        final filteredMap = <io.File, io.File?>{};
        for (final entry in filesMap.entries) {
          final pathLower = entry.key.path.toLowerCase();
          if (pathLower.endsWith('.srm') || pathLower.endsWith('.sav') || pathLower.endsWith('.gci')) {
            filteredMap[entry.key] = entry.value;
            break; // Keep only the first primary save file
          }
        }
        // Fallback if no specific extension matches: keep the first file entry if it's not a directory
        if (filteredMap.isEmpty) {
          for (final entry in filesMap.entries) {
            if (!await io.FileSystemEntity.isDirectory(entry.key.path)) {
              filteredMap[entry.key] = entry.value;
              break;
            }
          }
        }
        filesMap = filteredMap;
      }
      if (filesMap.isEmpty) return false;
      filesMap = await _unrzipFiles(game, filesMap);

      // --- Conflict Detection ---
      if (!force) {
        debugPrint('[SaveSync] [push] Checking for conflicts...');
        final latestRemote = await _rommService.getLatestSave(game.id);
        if (latestRemote != null) {
          final remoteTime = DateTime.tryParse(latestRemote['updated_at']?.toString() ?? '');
          final lastPull = _getLastPullTime(game.id);
          
          // If remote is newer than our last pull, and we have local changes -> Conflict!
          if (remoteTime != null && lastPull != null && remoteTime.isAfter(lastPull)) {
             // Find the newest local file time
             DateTime? localTime;
             for (final file in filesMap.keys) {
               final mtime = await file.lastModified();
               if (localTime == null || mtime.isAfter(localTime)) localTime = mtime;
             }
             
             if (localTime != null && remoteTime.isAfter(lastPull)) {
               throw SaveConflictException(
                 game: game,
                 localTime: localTime,
                 cloudTime: remoteTime,
                 cloudScreenshot: latestRemote['screenshot_path'] ?? latestRemote['screenshot_url'],
               );
             }
          }
        }
      }

      int uploaded = 0;
      final displayStem = game.displayName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final tempDir = await _directoryService.getEmulatorDirectory('temp');
      if (!await io.Directory(tempDir).exists()) {
        await io.Directory(tempDir).create(recursive: true);
      }

      io.File? finalUploadFile;
      io.File? finalScreenshotFile;
      String uploadFilename;
      bool isBundle = false;

      // Decide whether to bundle (zip) or upload directly
      // We bundle if there are multiple files, or if the single entry is a directory
      if (filesMap.length == 1 && !await io.FileSystemEntity.isDirectory(filesMap.keys.first.path)) {
        final entry = filesMap.entries.first;
        finalUploadFile = entry.key;
        finalScreenshotFile = entry.value;
        uploadFilename = p.basename(finalUploadFile.path);
        debugPrint('[SaveSync] [push] Mode: single file → $uploadFilename');
      } else {
        isBundle = true;
        debugPrint('[SaveSync] [push] Mode: bundle (${filesMap.length} files)');
        // --- Prepare unique bundle ZIP to bypass server-side deduplication ---
        final bundleToken = DateTime.now().millisecondsSinceEpoch;
        final bundleZipPath = p.join(tempDir, '$displayStem.bundle.$bundleToken.zip');
        final encoder = ZipFileEncoder();
        encoder.create(bundleZipPath);

        // 1. Write sync metadata (only for bundles to help with multi-file coherence).
        // Scoped to this call's bundleToken — a shared literal filename here
        // would race with any other concurrent push/pull writing/deleting
        // the same path in the same temp directory.
        final metaFile = io.File(p.join(tempDir, 'freegosy_sync.$bundleToken.txt'));
        await metaFile.writeAsString(await _bundleMetadata(strategy, game, romPath, filesMap));
        await encoder.addFile(metaFile, 'freegosy_sync.txt');
        await metaFile.delete();

        // 2. Add all files/folders from the map
        for (final entry in filesMap.entries) {
          final file = entry.key;
          if (await io.FileSystemEntity.isDirectory(file.path)) {
            await encoder.addDirectory(io.Directory(file.path), includeDirName: true);
          } else {
            await encoder.addFile(file, p.basename(file.path));
          }
        }
        encoder.close();
        
        finalUploadFile = io.File(bundleZipPath);
        uploadFilename = '$displayStem.zip';
        finalScreenshotFile = filesMap.values.firstWhere((s) => s != null, orElse: () => null);
        debugPrint('[SyncService] [legacy] _legacyPushSaves: mode=bundle');
      }

      // Reject empty/blank saves to prevent overwriting legitimate cloud saves.
      final fileLen = await finalUploadFile.length();
      if (fileLen < minValidSaveSizeBytes) {
        debugPrint('[SaveSync] [push] Rejected: $displayStem is only $fileLen bytes (min=$minValidSaveSizeBytes)');
        if (isBundle && await finalUploadFile.exists()) await finalUploadFile.delete();
        return false;
      }

      // RomM's hash of the upload (a zip by its contents): an unchanged save
      // keeps it even when its emulator rewrote the files.
      final String localHash =
          await rommHashOfSaveFile(finalUploadFile) ?? await _hashFile(finalUploadFile);
      final String? storedHash = _getStoredHash(game.id, uploadFilename);

      if (!force && storedHash != null && localHash == storedHash) {
        debugPrint('[SaveSync] [push] Hash unchanged — skipping upload');
        if (isBundle && await finalUploadFile.exists()) await finalUploadFile.delete();
        return true; 
      }

      // Upload with autocleanup and overwrite.
      // autocleanup=true: RomM prunes old saves in the same slot (keeps 5).
      // overwrite=force: Manual "Push" updates the existing record in place.
      // This replaces the old approach of client-side pruneOldSaves() which
      // made extra API calls. Server-side autocleanup is more efficient.
      final result = await _rommService.uploadSave(
        game.id,
        finalUploadFile,
        emulator: _saveEmulatorTag(strategy, game, emulatorId),
        screenshotFile: finalScreenshotFile,
        overrideFilename: uploadFilename,
        autocleanup: true,
        autocleanupLimit: 5,
        overwrite: force,
      );

      if (result.ok) {
        uploaded++;
        await _storeHash(game.id, uploadFilename, localHash);
        // RomM's newest save is now this PC's own: not a newer save from
        // elsewhere at the next push's conflict check.
        await _setLastPullTime(game.id);
        await _recordSyncedRommId(game, strategy, result.saved?['id']);
        debugPrint('[SaveSync] [push] Upload OK — $uploadFilename ($fileLen bytes) saved to RomM');
      } else {
        debugPrint('[SaveSync] [push] Upload FAILED');
      }

      if (isBundle && await finalUploadFile.exists()) await finalUploadFile.delete();

      debugPrint('[SaveSync] ─── PUSH END ─── ok=${uploaded > 0}');
      return uploaded > 0;
    } on SaveConflictException {
      rethrow;
    } on SaveSyncNotPossibleException {
      rethrow;
    } catch (e) {
      debugPrint('[SaveSync] [push] ERROR: $e');
      return false;
    }
  }

  /// Returns all available saves for [gameId] from RomM.
  Future<List<Map<String, dynamic>>> getSavesForGame(String gameId) async {
    return _rommService.getSavesList(gameId);
  }

  /// Checks if [data] begins with ZIP magic bytes (PK\x03\x04).
  bool _isZipBytes(Uint8List data) =>
      data.length >= 4 &&
      data[0] == 0x50 &&
      data[1] == 0x4B &&
      data[2] == 0x03 &&
      data[3] == 0x04;

  /// Ensures the filename matches the actual content format. If [data] is a
  /// ZIP but [filename] doesn't end with .zip, appends .zip so strategies
  /// can correctly extract the save inside. This makes manually-uploaded ZIPs
  /// and any ZIP whose cloud filename lacks the extension work seamlessly.
  String _adjustFilenameForFormat(Uint8List data, String filename) {
    if (filename.toLowerCase().endsWith('.zip')) return filename;
    if (_isZipBytes(data)) {
      return '${p.basenameWithoutExtension(filename)}.zip';
    }
    return filename;
  }

  /// Matches pure timestamp filenames like "2026-07-11_08-45-38"
  static final _timestampPattern = RegExp(r'^\d{4}-\d{2}-\d{2}[_-]\d{2}[_-]\d{2}[_-]\d{2}$');
  /// Matches RomM timestamp tags appended to filenames like "Game Name [2026-07-11_15-36-41]"
  static final _rommTimestampTag = RegExp(r'\s*\[\d{4}-\d{2}-\d{2}[ _]\d{2}-\d{2}-\d{2}(-\d+)?\]$');

  /// Strips any timestamp artifacts from [filename].
  ///
  /// RomM adds timestamp tags to filenames: "Game [2026-07-11_15-36-41].zip"
  /// These must be stripped before writing to disk so emulators can find
  /// the save file by matching the ROM name. Without this, emulators like
  /// melonDS and RetroArch fail to recognize the save (issues #42, #28).
  ///
  /// Also handles pure timestamp filenames (legacy artifacts) by replacing
  /// them with "save{ext}".
  @visibleForTesting
  static String normalizeSaveFilename(String filename) {
    var base = p.basenameWithoutExtension(filename);
    final ext = p.extension(filename);
    if (_timestampPattern.hasMatch(base)) return 'save$ext';
    base = base.replaceAll(_rommTimestampTag, '');
    if (base.isEmpty) return 'save$ext';
    return '$base$ext';
  }

  /// Legacy pull path for RomM versions prior to 4.9.
  /// Uses stored last-pull timestamps for freshness checks.
  Future<bool> _legacyPullSave(Game game, String romPath, {Map<String, dynamic>? saveData, String? coreOverride, String? emulatorId}) async {
    try {
      final strategy = getStrategyForGame(game, emulatorId: emulatorId);
      if (strategy == null) {
        debugPrint('[SaveSync] [pull] No save strategy for slug="${game.platformSlug}"');
        return false;
      }
      debugPrint('[SaveSync] [pull] Strategy: ${strategy.strategyId}  (legacy path)');

      _applyStrategyMappings(strategy, game, coreOverride: coreOverride);

      debugPrint('[SaveSync] [pull] Fetching latest save from server...');
      final Map<String, dynamic>? save = saveData ?? await _rommService.getLatestSave(game.id);
      if (save == null) {
        debugPrint('[SaveSync] [pull] No save found on server');
        return false;
      }

      if (saveData == null) {
        final remoteUpdatedAt = DateTime.tryParse(
            save['updated_at']?.toString() ?? '');
        final lastPull = _getLastPullTime(game.id);

        if (lastPull != null &&
            remoteUpdatedAt != null &&
            !remoteUpdatedAt.isAfter(lastPull)) {
          debugPrint('[SaveSync] [pull] Save not newer than last pull — skipping');
          return false;
        }
      }

      if (saveData == null && await _localSaveIsNewer(strategy, game, romPath, save)) {
        debugPrint('[SaveSync] [pull] The local save is newer than RomM\'s — keeping it');
        return false;
      }
      if (await _alreadyHave(strategy, game, romPath, save)) return false;

      final downloadUrl = save['download_path'] as String?
          ?? save['url'] as String?;
      if (downloadUrl == null) {
        debugPrint('[SaveSync] [pull] Save record found but no download URL');
        return false;
      }

      final filename = save['file_name'] as String?
          ?? downloadUrl.split('/').last;

      // Skip save states — only sync battery-backed saves
      final fnameLower = filename.toLowerCase();
      if (fnameLower.endsWith('.state') ||
          fnameLower.contains('.state.') ||
          fnameLower.endsWith('.state.auto') ||
          RegExp(r'\.state\d+$').hasMatch(fnameLower)) {
        debugPrint('[SaveSync] [pull] Skipping — cloud save is a state file ($filename)');
        return false;
      }

      final downloaded = await _rommService.downloadSave(downloadUrl);
      if (downloaded == null) {
        debugPrint('[SaveSync] [pull] Download failed');
        return false;
      }
      final bytes = await _unrzipDownload(downloaded, filename);

      // Sniff actual bytes so that ZIP files (even those manually uploaded or
      // stored under a non-.zip name) are correctly extracted on restore.
      final adjustedFilename = _adjustFilenameForFormat(bytes, normalizeSaveFilename(filename));
      debugPrint('[SaveSync] [pull] Downloaded ${bytes.length} bytes → restoring as "$adjustedFilename"');

      if (SaveRestoreGuard.restoreTooLate) {
        debugPrint('[SaveSync] [pull] The launch went ahead without this pull — not restoring "$adjustedFilename"');
        return false;
      }
      // The download is the save already on this PC (RomM sent no hash, or
      // one that didn't match): nothing to write, and the save is RomM's.
      if (await _haveRommSave(strategy, game, romPath, save, rommHashOfUpload(bytes))) {
        debugPrint('[SaveSync] [pull] The downloaded save is the one on this PC — kept as it is');
        await _setLastPullTime(game.id);
        return true;
      }
      // A strategy can take a download and keep nothing of it (DuckStation and
      // a file that is no memory card): then nothing was pulled.
      final before = await _fingerprintOf(strategy, game, romPath, 'saves');
      final ok = await _restoreDownloaded(strategy, game, romPath, bytes, adjustedFilename,
          sourceTag: save['emulator']?.toString(), emulatorId: emulatorId);

      if (ok && await _restoredNothing(strategy, game, romPath, before)) return false;
      if (ok) {
        await _setLastPullTime(game.id);
        await _recordSyncedRommId(game, strategy, save['id']);
        debugPrint('[SaveSync] ─── PULL END ─── restored OK');
      } else {
        debugPrint('[SaveSync] [pull] Strategy failed to restore save');
        throw Exception('Strategy [${strategy.strategyId}] failed to restore save file: $filename');
      }
      return ok;
    } on io.FileSystemException catch (e) {
      throw Exception('Disk Error: ${e.message} (Path: ${e.path})');
    } on DioException catch (e) {
      throw Exception('Network Error: ${e.message} (Status: ${e.response?.statusCode})');
    } catch (e) {
      if (e.toString().contains('Exception: ')) rethrow;
      throw Exception('Pull Failed: $e');
    }
  }

  WindowsSaveStrategy get windowsSaveStrategy => _windows;
  EdenSaveStrategy get edenSaveStrategy => _eden;
  AzaharSaveStrategy get azaharSaveStrategy => _azahar;

  void setNdsCore(String core) {
    _retroarch.setNdsCore(core);
  }

  void loadCoreOverrides(Map<String, String> overrides) {
    _retroarch.loadCoreOverrides(overrides);
  }

  /// Applies the user's choice after a [SaveConflictException]: 'local' force-pushes
  /// the local save, 'cloud' pulls and restores the cloud save. Returns the underlying
  /// pushSaves/pullSave result, or false if [choice] is neither.
  Future<bool> resolveConflict(
    Game game,
    String romPath,
    SaveConflictException e, {
    required String choice,
    required String syncMode,
  }) async {
    if (choice == 'local') {
      return pushSaves(game, romPath, syncMode: syncMode, force: true);
    } else if (choice == 'cloud') {
      return pullSave(game, romPath);
    }
    return false;
  }
}
