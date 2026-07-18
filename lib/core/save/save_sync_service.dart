import 'dart:io' as io;
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../romm/romm_models.dart';
import '../romm/romm_service.dart';
import '../storage/directory_service.dart';
import 'save_strategy.dart';
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
  final SharedPreferences _prefs;

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

  SaveSyncService(this._rommService, this._directoryService, this._strategyRegistry, this._prefs) {
    _retroarch = RetroArchSaveStrategy(_directoryService);
    _dolphin = DolphinSaveStrategy(_directoryService);
    _eden = EdenSaveStrategy(_directoryService, onMappingResolved: saveMappedFolder);
    _ryujinx = RyujinxSaveStrategy(onMappingResolved: saveMappedFolder);
    _windows = WindowsSaveStrategy(_prefs);
    _pcsx2 = Pcsx2SaveStrategy(_directoryService);
    _rpcs3 = Rpcs3SaveStrategy(_directoryService);
    _xenia = XeniaSaveStrategy(_directoryService);
    _duckstation = DuckstationSaveStrategy(_directoryService);
    _melonds = MelonDsSaveStrategy(_directoryService);
    _mgba = MgbaSaveStrategy(_directoryService);
    _ppsspp = PpssppSaveStrategy(_directoryService);
    _cemu = CemuSaveStrategy(_directoryService);
    _azahar = AzaharSaveStrategy(_directoryService, onMappingResolved: saveMappedFolder);
    _ares = AresSaveStrategy(_directoryService);
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
  SaveStrategy? getStrategyForSlug(String? platformSlug) {
    if (platformSlug != null) {
      final preferredId = _strategyRegistry.getPreferredEmulatorId(platformSlug);
      if (preferredId != null) {
        return _saveStrategyForEmulatorId(preferredId);
      }

      // No user preference set: check which emulator the registry would use
      // by default (first registered strategy that supports this slug).
      final defaultEmulatorStrategy = _strategyRegistry.getStrategyForSlug(platformSlug);
      if (defaultEmulatorStrategy != null) {
        return _saveStrategyForEmulatorId(defaultEmulatorStrategy.emulatorId);
      }
    }

    // Hardcoded fallback (should rarely be reached)
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
        return null;
    }
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
    if (id == 'windows') return _windows;
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
    debugPrint('[SyncService] Cleared hash cache for game $gameId');
  }

  Future<String> _hashFile(io.File file) async {
    final bytes = await file.readAsBytes();
    return md5.convert(bytes).toString();
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
  Future<bool> pushSaves(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both', bool force = false}) async {
    final caps = await _rommService.fetchCapabilities();
    if (caps.hasDeviceSaveSync) {
      return _devicePushSaves(game, romPath,
          sessionStart: sessionStart, syncMode: syncMode, force: force);
    }
    return _legacyPushSaves(game, romPath,
        sessionStart: sessionStart, syncMode: syncMode, force: force);
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
  Future<bool> pullSave(Game game, String romPath, {Map<String, dynamic>? saveData}) async {
    final now = DateTime.now();
    final lastCheck = _lastPullCheck[game.id];
    if (saveData == null && lastCheck != null && now.difference(lastCheck) < _pullCheckCooldown) {
      debugPrint('[SyncService] Skipping pull for ${game.displayName}: checked ${now.difference(lastCheck).inSeconds}s ago');
      return false;
    }
    _lastPullCheck[game.id] = now;

    final caps = await _rommService.fetchCapabilities();
    if (caps.hasDeviceSaveSync) {
      return _devicePullSave(game, romPath, saveData: saveData);
    }
    return _legacyPullSave(game, romPath, saveData: saveData);
  }

  // ---------------------------------------------------------------------------
  // Helpers shared by both paths
  // ---------------------------------------------------------------------------

  String? _getDeviceId() => _prefs.getString('romm_device_id');

  void _applyStrategyMappings(SaveStrategy strategy, Game game) {
    if (strategy is EdenSaveStrategy) {
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
    if (strategy.shouldZip) return filesMap;
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
      {DateTime? sessionStart, String syncMode = 'both', bool force = false}) async {
    try {
      final strategy = getStrategyForSlug(game.platformSlug);
      if (strategy == null) return false;
      _applyStrategyMappings(strategy, game);

      var filesMap = await strategy.getSaveFilesWithScreenshots(
        game, romPath,
        sessionStart: sessionStart,
        syncMode: syncMode,
      );
      if (filesMap.isEmpty) return false;
      filesMap = _filterFilesMap(strategy, filesMap);
      if (filesMap.isEmpty) return false;

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
      } else {
        isBundle = true;
        final bundleZipPath = p.join(
            tempDir,
            '$displayStem.bundle.${DateTime.now().millisecondsSinceEpoch}.zip');
        final encoder = ZipFileEncoder();
        encoder.create(bundleZipPath);
        final metaFile = io.File(p.join(tempDir, 'freegosy_sync.txt'));
        await metaFile.writeAsString(DateTime.now().toIso8601String());
        await encoder.addFile(metaFile);
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
        debugPrint(
            '[SyncService] Rejecting save for $displayStem: $fileLen bytes < $minValidSaveSizeBytes min');
        if (isBundle && await finalUploadFile.exists()) {
          await finalUploadFile.delete();
        }
        return false;
      }

      final String localHash = await _hashFile(finalUploadFile);
      final String? storedHash = _getStoredHash(game.id, uploadFilename);

      if (!force && storedHash != null && localHash == storedHash) {
        debugPrint(
            '[SyncService] Skipping upload for $displayStem: hash unchanged ($localHash)');
        if (isBundle && await finalUploadFile.exists()) {
          await finalUploadFile.delete();
        }
        return true;
      }

      final deviceId = _getDeviceId();
      final result = await _rommService.uploadSave(
        game.id,
        finalUploadFile,
        deviceId: deviceId,
        slot: 'freegosy',
        autocleanup: true,
        autocleanupLimit: 5,
        overwrite: force,
        screenshotFile: finalScreenshotFile,
        overrideFilename: uploadFilename,
      );

      if (!result.ok && result.conflict != null) {
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
        debugPrint(
            '[SyncService] [4.9] Pushed save for $displayStem (force=$force)');
      }

      if (isBundle && await finalUploadFile.exists()) await finalUploadFile.delete();
      final metaFile = io.File(p.join(tempDir, 'freegosy_sync.txt'));
      if (await metaFile.exists()) await metaFile.delete();
      return result.ok;
    } on SaveConflictException {
      rethrow;
    } catch (e) {
      debugPrint('[SyncService] [4.9] Error in _devicePushSaves: $e');
      return false;
    }
  }

  Future<bool> _devicePullSave(Game game, String romPath,
      {Map<String, dynamic>? saveData}) async {
    try {
      final strategy = getStrategyForSlug(game.platformSlug);
      if (strategy == null) return false;
      _applyStrategyMappings(strategy, game);

      final deviceId = _getDeviceId();
      final Map<String, dynamic>? save =
          saveData ?? await _rommService.getLatestSave(game.id, deviceId: deviceId);
      if (save == null) return false;

      // If server says we already have the current version, skip
      if (saveData == null && deviceId != null) {
        final syncs = save['device_syncs'] as List<dynamic>?;
        final mySync = syncs?.firstWhere(
          (d) => d['device_id'] == deviceId,
          orElse: () => null,
        );
        if (mySync != null && mySync['is_current'] == true) {
          debugPrint(
              '[SyncService] [4.9] Already current for ${game.displayName}, skipping pull');
          return false;
        }
      }

      final downloadUrl =
          save['download_path'] as String? ?? save['url'] as String?;
      if (downloadUrl == null) return false;

      final filename =
          save['file_name'] as String? ?? downloadUrl.split('/').last;

      // Skip save states — only sync battery-backed saves (.srm, .sav, .sra, etc.)
      final fnameLower = filename.toLowerCase();
      if (fnameLower.endsWith('.state') ||
          fnameLower.contains('.state.') ||
          fnameLower.endsWith('.state.auto') ||
          RegExp(r'\.state\d+$').hasMatch(fnameLower)) {
        debugPrint(
            '[SyncService] Skipping pull for ${game.displayName}: latest cloud save is a state file ($filename)');
        return false;
      }

      final bytes = await _rommService.downloadSave(downloadUrl, deviceId: deviceId);
      if (bytes == null) return false;

      final adjustedFilename = _adjustFilenameForFormat(bytes, normalizeSaveFilename(filename));

      final ok = await strategy.restoreSave(game, romPath, bytes, adjustedFilename);
      if (!ok) {
        throw Exception(
            'Strategy [${strategy.strategyId}] failed to restore save: $filename');
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

  // ---------------------------------------------------------------------------
  // Legacy sync (RomM < 4.9) — kept for backward compatibility
  // ---------------------------------------------------------------------------

  /// Legacy upload path for RomM versions prior to 4.9.
  /// Uses timestamp-based conflict detection and manual save pruning.
  Future<bool> _legacyPushSaves(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both', bool force = false}) async {
    try {
      final strategy = getStrategyForSlug(game.platformSlug);
      if (strategy == null) return false;

      _applyStrategyMappings(strategy, game);

      var filesMap = await strategy.getSaveFilesWithScreenshots(
        game, romPath,
        sessionStart: sessionStart,
        syncMode: syncMode,
      );
      if (filesMap.isEmpty) return false;

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

      // --- Conflict Detection ---
      if (!force) {
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
        debugPrint('[Sync] Uploading single save file directly: $uploadFilename');
      } else {
        isBundle = true;
        // --- Prepare unique bundle ZIP to bypass server-side deduplication ---
        final bundleZipPath = p.join(tempDir, '$displayStem.bundle.${DateTime.now().millisecondsSinceEpoch}.zip');
        final encoder = ZipFileEncoder();
        encoder.create(bundleZipPath);

        // 1. Write sync metadata (only for bundles to help with multi-file coherence)
        final metaFile = io.File(p.join(tempDir, 'freegosy_sync.txt'));
        await metaFile.writeAsString(DateTime.now().toIso8601String());
        await encoder.addFile(metaFile);

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
        debugPrint('[Sync] Uploading bundled save: $uploadFilename');
      }

      // Reject empty/blank saves to prevent overwriting legitimate cloud saves.
      final fileLen = await finalUploadFile.length();
      if (fileLen < minValidSaveSizeBytes) {
        debugPrint('[SyncService] [legacy] Rejecting save for $displayStem: $fileLen bytes < $minValidSaveSizeBytes min');
        if (isBundle && await finalUploadFile.exists()) await finalUploadFile.delete();
        return false;
      }

      final String localHash = await _hashFile(finalUploadFile);
      final String? storedHash = _getStoredHash(game.id, uploadFilename);

      // Local deduplication check (only for automatic syncs)
      // When force=true (manual "Push" button), this check is bypassed.
      // Previously, the lack of force=true on manual push meant saves
      // with unchanged content were never re-uploaded. Now the "Push"
      // button passes force=true which sets overwrite=true on the server.
      if (!force && storedHash != null && localHash == storedHash) {
        debugPrint('[Sync] Skipping upload for $displayStem: hash matches local cache ($localHash)');
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
        screenshotFile: finalScreenshotFile,
        overrideFilename: uploadFilename,
        autocleanup: true,
        autocleanupLimit: 5,
        overwrite: force,
      );

      if (result.ok) {
        uploaded++;
        await _storeHash(game.id, uploadFilename, localHash);
        debugPrint('[SyncService] [legacy] Pushed save for $displayStem (force=$force)');
      }

      if (isBundle && await finalUploadFile.exists()) await finalUploadFile.delete();
      final metaFile = io.File(p.join(tempDir, 'freegosy_sync.txt'));
      if (await metaFile.exists()) await metaFile.delete();

      return uploaded > 0;
    } on SaveConflictException {
      rethrow;
    } catch (e) {
      debugPrint('[SyncService] [legacy] Error in _legacyPushSaves: $e');
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
  Future<bool> _legacyPullSave(Game game, String romPath, {Map<String, dynamic>? saveData}) async {
    try {
      final strategy = getStrategyForSlug(game.platformSlug);
      if (strategy == null) return false;

      _applyStrategyMappings(strategy, game);

      final Map<String, dynamic>? save = saveData ?? await _rommService.getLatestSave(game.id);
      if (save == null) return false;

      if (saveData == null) {
        final remoteUpdatedAt = DateTime.tryParse(
            save['updated_at']?.toString() ?? '');
        final lastPull = _getLastPullTime(game.id);

        if (lastPull != null &&
            remoteUpdatedAt != null &&
            !remoteUpdatedAt.isAfter(lastPull)) {
          return false;
        }
      }

      final downloadUrl = save['download_path'] as String?
          ?? save['url'] as String?;
      if (downloadUrl == null) return false;

      final filename = save['file_name'] as String?
          ?? downloadUrl.split('/').last;

      // Skip save states — only sync battery-backed saves
      final fnameLower = filename.toLowerCase();
      if (fnameLower.endsWith('.state') ||
          fnameLower.contains('.state.') ||
          fnameLower.endsWith('.state.auto') ||
          RegExp(r'\.state\d+$').hasMatch(fnameLower)) {
        debugPrint('[SyncService] [legacy] Skipping pull for ${game.displayName}: latest save is a state file ($filename)');
        return false;
      }

      final bytes = await _rommService.downloadSave(
          downloadUrl);
      if (bytes == null) return false;

      // Sniff actual bytes so that ZIP files (even those manually uploaded or
      // stored under a non-.zip name) are correctly extracted on restore.
      final adjustedFilename = _adjustFilenameForFormat(bytes, normalizeSaveFilename(filename));

      final ok = await strategy.restoreSave(
          game, romPath, bytes, adjustedFilename);

      if (ok) {
        await _setLastPullTime(game.id);
      } else {
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
}
