import 'dart:io';
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

  SaveSyncService(this._rommService, this._directoryService, this._strategyRegistry) {
    _retroarch = RetroArchSaveStrategy(_directoryService);
    _dolphin = DolphinSaveStrategy(_directoryService);
    _eden = EdenSaveStrategy();
    _windows = WindowsSaveStrategy();
    _pcsx2 = Pcsx2SaveStrategy(_directoryService);
    _rpcs3 = Rpcs3SaveStrategy(_directoryService);
    _xenia = XeniaSaveStrategy(_directoryService);
    _duckstation = DuckstationSaveStrategy(_directoryService);
    _melonds = MelonDsSaveStrategy();
    _mgba = MgbaSaveStrategy();
    _ppsspp = PpssppSaveStrategy(_directoryService);
    _cemu = CemuSaveStrategy(_directoryService);
  }

  /// Returns the appropriate save strategy for [platformSlug], or null if unsupported.
  SaveStrategy? getStrategyForSlug(String? platformSlug) {
    // print('[SaveSync] getStrategyForSlug called with: $platformSlug');
    if (platformSlug != null) {
      final preferredId = _strategyRegistry.getPreferredEmulatorId(platformSlug);
      // print('[SaveSync] preferredId for $platformSlug: $preferredId');
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
      case 'xbox':
        return null;
      default:
        return null;
    }
  }

  /// Uploads all local save files for [game] to RomM.
  ///
  /// If [sessionStart] is provided, only files modified after that time are uploaded.
  /// Returns true if at least one file was uploaded successfully.
  Future<bool> pushSaves(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    try {
      final strategy = getStrategyForSlug(game.platformSlug);
      if (strategy == null) {
        return false;
      }

      final files = await strategy.getSaveFiles(game, romPath, sessionStart: sessionStart, syncMode: syncMode);
      if (files.isEmpty) {
        return false;
      }

      int uploaded = 0;
      for (final file in files) {
        File uploadFile = file;
        bool isTempZip = false;

        // If it's a directory, zip it first
        if (await FileSystemEntity.isDirectory(file.path)) {
          final zipPath = '${file.path}.zip';
          final encoder = ZipFileEncoder();
          encoder.create(zipPath);
          await encoder.addDirectory(Directory(file.path));
          encoder.close();
          uploadFile = File(zipPath);
          isTempZip = true;
        }

  final ok = await _rommService.uploadSave(game.id, uploadFile);
  if (ok) uploaded++;

  // Clean up temp zip
  if (isTempZip && await uploadFile.exists()) {
    await uploadFile.delete();
  }
}

      return uploaded > 0;
    } catch (e) {
      return false;
    }
  }

  /// Downloads the latest save for [game] from RomM and restores it locally.
  ///
  /// Returns true on success.
  Future<bool> pullSave(Game game, String romPath) async {
    try {
      final strategy = getStrategyForSlug(game.platformSlug);
      if (strategy == null) {
        return false;
      }

      final save = await _rommService.getLatestSave(game.id);
      if (save == null) {
        return false;
      }
      // print('[Pull] getLatestSave result: $save');

      final downloadUrl = save['download_path'] as String? ?? save['url'] as String?;
      if (downloadUrl == null) {
        return false;
      }

      final bytes = await _rommService.downloadSave(downloadUrl);
      if (bytes == null) {
        return false;
      }
      // print('[Pull] downloaded bytes: ${bytes?.length}');

      final filename = save['file_name'] as String? ??
          downloadUrl.split('/').last;

      final ok = await strategy.restoreSave(game, romPath, bytes, filename);
      // print('[Pull] restoreSave result: $ok');
      return ok;
    } catch (e) {
      // print('[Pull] error: $e'); // Removed print statement
      rethrow;
    }
  }

  WindowsSaveStrategy get windowsSaveStrategy => _windows;
}
