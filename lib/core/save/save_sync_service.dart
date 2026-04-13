import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../romm/romm_models.dart';
import '../romm/romm_service.dart';
import '../storage/directory_service.dart';
import 'save_strategy.dart';
import 'strategies/retroarch_save_strategy.dart';
import 'strategies/dolphin_save_strategy.dart';
import 'strategies/eden_save_strategy.dart';
import 'package:archive/archive_io.dart';
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

class SaveSyncService {
  final RommService _rommService;
  final DirectoryService _directoryService;
  final StrategyRegistry _strategyRegistry;

  late final RetroArchSaveStrategy _retroarch;
  late final DolphinSaveStrategy _dolphin;
  late final EdenSaveStrategy _eden;
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

  SaveSyncService(this._rommService, this._directoryService, this._strategyRegistry) {
    _retroarch = RetroArchSaveStrategy(_directoryService);
    _dolphin = DolphinSaveStrategy(_directoryService);
    _eden = EdenSaveStrategy(_directoryService, onMappingResolved: saveMappedFolder);
    _windows = WindowsSaveStrategy();
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
  Future<String?> getMappedFolder(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('eden_mapping_$gameId');
  }

  /// Saves the manual Title ID mapping for a given game.
  Future<void> saveMappedFolder(String gameId, String folderName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('eden_mapping_$gameId', folderName);
  }

  /// Returns the manual Eden profile choice.
  Future<String?> getActiveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('active_eden_profile');
  }

  /// Saves the manual Eden profile choice.
  Future<void> saveActiveProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_eden_profile', profileId);
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
        return _eden;
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

  Future<String?> _getStoredHash(
      String gameId, String filename) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_hashKey(gameId, filename));
  }

  Future<void> _storeHash(
      String gameId, String filename, String hash) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hashKey(gameId, filename), hash);
  }

  /// Clears the stored hash for a game, forcing the next push to upload.
  Future<void> clearHashCache(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('last_hash_${gameId}_'));
    for (final key in keys) {
      await prefs.remove(key);
    }
    debugPrint('[SyncService] Cleared hash cache for game $gameId');
  }

  Future<String> _hashFile(File file) async {
    final bytes = await file.readAsBytes();
    return md5.convert(bytes).toString();
  }

  String _pullKey(String gameId) =>
      'last_pull_$gameId';

  Future<DateTime?> _getLastPullTime(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_pullKey(gameId));
    if (stored == null) return null;
    return DateTime.tryParse(stored);
  }

  Future<void> _setLastPullTime(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
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
        final mapping = await getMappedFolder(game.id);
        strategy.setManualMapping(mapping);
        final activeProfile = await getActiveProfile();
        strategy.setActiveProfileOverride(activeProfile);
      } else if (strategy is AzaharSaveStrategy) {
        final mapping = await getMappedFolder(game.id);
        strategy.setManualMapping(mapping);
      }

      final filesMap = await strategy.getSaveFilesWithScreenshots(
        game, romPath,
        sessionStart: sessionStart,
        syncMode: syncMode,
      );
      if (filesMap.isEmpty) return false;

      int uploaded = 0;
      for (final entry in filesMap.entries) {
        final file = entry.key;
        final screenshotFile = entry.value;
        File uploadFile = file;
        bool isTempZip = false;

        if (await FileSystemEntity.isDirectory(file.path)) {
          final zipPath = '${file.path}.zip';
          // Write a temp metadata file into the save dir before zipping.
          // This gives each zip a unique content hash so RomM won't deduplicate.
          final metaFile = File('${file.path}/.freegosy_sync');
          await metaFile.writeAsString(DateTime.now().toIso8601String());
          final encoder = ZipFileEncoder();
          encoder.create(zipPath);
          await encoder.addDirectory(Directory(file.path));
          encoder.close();
          // Clean up the temp meta file
          if (await metaFile.exists()) await metaFile.delete();
          uploadFile = File(zipPath);
          isTempZip = true;
        }

        final filename = uploadFile.path
            .split(RegExp(r'[/\\]'))
            .last;

        final localHash = await _hashFile(uploadFile);
        final storedHash = await _getStoredHash(game.id, filename);

        if (!force && storedHash != null && localHash == storedHash) {
          if (isTempZip && await uploadFile.exists()) {
            await uploadFile.delete();
          }
          continue;
        }

        final ok = await _rommService.uploadSave(game.id, uploadFile, screenshotFile: screenshotFile);
        if (ok) {
          uploaded++;
          await _storeHash(game.id, filename, localHash);
        }

        if (isTempZip && await uploadFile.exists()) {
          await uploadFile.delete();
        }
      }

      if (uploaded > 0) {
        await _rommService.pruneOldSaves(game.id);
      }
      return uploaded > 0;
    } catch (e) {
      rethrow;
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
        final mapping = await getMappedFolder(game.id);
        strategy.setManualMapping(mapping);
        final activeProfile = await getActiveProfile();
        strategy.setActiveProfileOverride(activeProfile);
      } else if (strategy is AzaharSaveStrategy) {
        final mapping = await getMappedFolder(game.id);
        strategy.setManualMapping(mapping);
      }

      final Map<String, dynamic>? save = saveData ?? await _rommService.getLatestSave(game.id);
      if (save == null) return false;

      if (saveData == null) {
        final remoteUpdatedAt = DateTime.tryParse(
            save['updated_at']?.toString() ?? '');
        final lastPull = await _getLastPullTime(game.id);

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
      }
      return ok;
    } catch (e) {
      rethrow;
    }
  }

  WindowsSaveStrategy get windowsSaveStrategy => _windows;
  EdenSaveStrategy get edenSaveStrategy => _eden;
  AzaharSaveStrategy get azaharSaveStrategy => _azahar;
}
