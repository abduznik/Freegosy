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
        final id = preferredId.toLowerCase();
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
      }
    }

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
        return _retroarch;
      case 'nds':
      case 'nintendo-ds':
      case 'ds':
        return _melonds;
      case 'psx':
      case 'ps1':
      case 'playstation':
        return _duckstation;
      case 'psp':
      case 'playstation-portable':
        return _ppsspp;
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

  /// Uploads all local save files for [game] to RomM.
  Future<bool> pushSaves(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both', bool force = false}) async {
    try {
      final strategy = getStrategyForSlug(game.platformSlug);
      if (strategy == null) return false;

      if (strategy is EdenSaveStrategy) {
        final mapping = getMappedFolder(game.id);
        strategy.setManualMapping(mapping);
        final activeProfile = getActiveProfile();
        strategy.setActiveProfileOverride(activeProfile);
      } else if (strategy is RyujinxSaveStrategy) {
        final mapping = getMappedFolder(game.id);
        strategy.setManualMapping(mapping);
        final activeProfile = getActiveProfile();
        strategy.setActiveProfileOverride(activeProfile);
      } else if (strategy is AzaharSaveStrategy) {
        final mapping = getMappedFolder(game.id);
        strategy.setManualMapping(mapping);
      }

      final filesMap = await strategy.getSaveFilesWithScreenshots(
        game, romPath,
        sessionStart: sessionStart,
        syncMode: syncMode,
      );
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

      final String localHash = await _hashFile(finalUploadFile);
      final String? storedHash = _getStoredHash(game.id, uploadFilename);

      // Local deduplication check (only for automatic syncs)
      if (!force && storedHash != null && localHash == storedHash) {
        debugPrint('[Sync] Skipping upload for $displayStem: hash matches local cache ($localHash)');
        if (isBundle && await finalUploadFile.exists()) await finalUploadFile.delete();
        return true; 
      }

      final ok = await _rommService.uploadSave(
        game.id, 
        finalUploadFile, 
        screenshotFile: finalScreenshotFile,
        overrideFilename: uploadFilename,
      );
      
      if (ok) {
        uploaded++;
        await _storeHash(game.id, uploadFilename, localHash);
        debugPrint('[Sync] Successfully pushed save for $displayStem (forced: $force)');
      }

      if (isBundle && await finalUploadFile.exists()) await finalUploadFile.delete();
      final metaFile = io.File(p.join(tempDir, 'freegosy_sync.txt'));
      if (await metaFile.exists()) await metaFile.delete();

      if (uploaded > 0) {
        await _rommService.pruneOldSaves(game.id);
      }
      return uploaded > 0;
    } on SaveConflictException {
      rethrow;
    } catch (e) {
      debugPrint('[Sync] Error in pushSaves: $e');
      return false;
    }
  }

  /// Returns all available saves for [gameId] from RomM.
  Future<List<Map<String, dynamic>>> getSavesForGame(String gameId) async {
    return _rommService.getSavesList(gameId);
  }

  /// Downloads a specific save for [game] from RomM and restores it locally.
  Future<bool> pullSave(Game game, String romPath, {Map<String, dynamic>? saveData}) async {
    try {
      final strategy = getStrategyForSlug(game.platformSlug);
      if (strategy == null) return false;

      if (strategy is EdenSaveStrategy) {
        final mapping = getMappedFolder(game.id);
        strategy.setManualMapping(mapping);
        final activeProfile = getActiveProfile();
        strategy.setActiveProfileOverride(activeProfile);
      } else if (strategy is RyujinxSaveStrategy) {
        final mapping = getMappedFolder(game.id);
        strategy.setManualMapping(mapping);
        final activeProfile = getActiveProfile();
        strategy.setActiveProfileOverride(activeProfile);
      } else if (strategy is AzaharSaveStrategy) {
        final mapping = getMappedFolder(game.id);
        strategy.setManualMapping(mapping);
      }

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

      final bytes = await _rommService.downloadSave(
          downloadUrl);
      if (bytes == null) return false;

      final filename = save['file_name'] as String?
          ?? downloadUrl.split('/').last;

      final ok = await strategy.restoreSave(
          game, romPath, bytes, filename);

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
}
