import 'dart:io';
import 'package:flutter/rendering.dart';
import '../romm/romm_models.dart';
import '../romm/romm_service.dart';
import '../storage/directory_service.dart';
import 'save_strategy.dart';
import 'strategies/retroarch_save_strategy.dart';
import 'strategies/dolphin_save_strategy.dart';
import 'strategies/eden_save_strategy.dart';
import 'package:archive/archive_io.dart';

class SaveSyncService {
  final RommService _rommService;
  final DirectoryService _directoryService;

  late final RetroArchSaveStrategy _retroarch;
  late final DolphinSaveStrategy _dolphin;
  late final EdenSaveStrategy _eden;

  SaveSyncService(this._rommService, this._directoryService) {
    _retroarch = RetroArchSaveStrategy(_directoryService);
    _dolphin = DolphinSaveStrategy(_directoryService);
    _eden = EdenSaveStrategy();
  }

  /// Returns the appropriate save strategy for [platformSlug], or null if unsupported.
  SaveStrategy? getStrategyForSlug(String? platformSlug) {
    switch (platformSlug?.toLowerCase()) {
      case 'gba':
      case 'gbc':
      case 'gb':
      case 'snes':
      case 'nes':
      case 'n64':
      case 'nds':
      case 'psx':
      case 'ps1':
      case 'playstation':
      case 'psp':
      case 'dc':
      case 'dreamcast':
      case 'megadrive':
      case 'genesis':
      case 'md':
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
      // These emulators don't have save sync yet
      case 'ps3':
      case 'playstation-3':
      case 'playstation3':
      case 'ps2':
      case 'playstation-2':
      case 'playstation2':
      case '3ds':
      case 'n3ds':
      case 'nintendo-3ds':
      case 'nintendo3ds':
      case 'new-nintendo-3ds':
      case 'new-nintendo-3ds-xl':
      case 'wiiu':
      case 'wii-u':
      case 'nintendo-wii-u':
      case 'nintendo-wiiu':
      case 'xbox':
      case 'xbox360':
      case 'xbla':
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
        debugPrint('[SaveSyncService] no strategy for ${game.platformSlug}');
        return false;
      }

      final files = await strategy.getSaveFiles(game, romPath, sessionStart: sessionStart, syncMode: syncMode);
      if (files.isEmpty) {
        debugPrint('[SaveSyncService] no save files found for ${game.name}');
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

      debugPrint('[SaveSyncService] pushed $uploaded/${files.length} saves for ${game.name}');
      return uploaded > 0;
    } catch (e) {
      debugPrint('[SaveSyncService] pushSaves error: $e');
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
        debugPrint('[SaveSyncService] no strategy for ${game.platformSlug}');
        return false;
      }

      final save = await _rommService.getLatestSave(game.id);
      if (save == null) {
        debugPrint('[SaveSyncService] no cloud save for ${game.name}');
        return false;
      }

      final downloadUrl = save['download_path'] as String? ?? save['url'] as String?;
      if (downloadUrl == null) {
        debugPrint('[SaveSyncService] save has no download URL');
        return false;
      }

      final bytes = await _rommService.downloadSave(downloadUrl);
      if (bytes == null) {
        debugPrint('[SaveSyncService] failed to download save bytes');
        return false;
      }

      final filename = save['file_name'] as String? ??
          downloadUrl.split('/').last;

      debugPrint('[SaveSyncService] calling restoreSave: filename=$filename romPath=$romPath bytesLen=${bytes.length}');
      final ok = await strategy.restoreSave(game, romPath, bytes, filename);
      debugPrint('[SaveSyncService] restoreSave returned: $ok');
      debugPrint('[SaveSyncService] pullSave ${ok ? 'ok' : 'failed'} for ${game.name}');
      return ok;
    } catch (e) {
      debugPrint('[SaveSyncService] pullSave error: $e');
      rethrow;
    }
  }
}
