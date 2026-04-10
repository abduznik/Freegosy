import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';

class FirmwareService {
  final RommService _rommService;
  final DirectoryService _directoryService;
  final StrategyRegistry _strategyRegistry;

  FirmwareService(this._rommService, this._directoryService, this._strategyRegistry);

  /// Downloads all available firmware for all platforms and places them in the appropriate emulator BIOS directories.
  Future<void> syncAllFirmware() async {
    try {
      final platforms = await _rommService.getPlatforms();
      for (final platform in platforms) {
        if (platform.firmware.isEmpty) continue;

        final strategy = _strategyRegistry.getStrategyForSlug(platform.slug);
        if (strategy == null) {
          debugPrint('[FirmwareService] No emulator found for platform: ${platform.slug}');
          continue;
        }

        final biosDir = await _directoryService.getEmulatorBiosDirectory(strategy.emulatorId);
        
        for (final firmware in platform.firmware) {
          await _downloadAndPlaceFirmware(firmware, biosDir);
        }
      }
    } catch (e) {
      debugPrint('[FirmwareService] Error syncing firmware: $e');
    }
  }

  /// Downloads firmware for a specific platform and places it in the emulator's BIOS directory.
  Future<void> syncFirmwareForPlatform(String platformSlug) async {
    try {
      final platforms = await _rommService.getPlatforms();
      final platform = platforms.firstWhere((p) => p.slug == platformSlug, orElse: () => throw Exception('Platform not found: $platformSlug'));
      
      if (platform.firmware.isEmpty) return;

      final strategy = _strategyRegistry.getStrategyForSlug(platform.slug);
      if (strategy == null) {
        debugPrint('[FirmwareService] No emulator found for platform: ${platform.slug}');
        return;
      }

      final biosDir = await _directoryService.getEmulatorBiosDirectory(strategy.emulatorId);
      
      for (final firmware in platform.firmware) {
        await _downloadAndPlaceFirmware(firmware, biosDir);
      }
    } catch (e) {
      debugPrint('[FirmwareService] Error syncing firmware for $platformSlug: $e');
    }
  }

  Future<void> _downloadAndPlaceFirmware(Firmware firmware, String biosDir) async {
    final destPath = p.join(biosDir, firmware.fileName);
    final destFile = File(destPath);

    if (await destFile.exists()) {
      // TODO: Could check MD5 hash here if needed, but for now just skip if exists
      debugPrint('[FirmwareService] Firmware already exists: ${firmware.fileName}');
      return;
    }

    debugPrint('[FirmwareService] Downloading firmware: ${firmware.fileName} to $destPath');
    final bytes = await _rommService.downloadFirmware(firmware);
    if (bytes != null) {
      await destFile.writeAsBytes(bytes);
      debugPrint('[FirmwareService] Successfully saved firmware: ${firmware.fileName}');
    } else {
      debugPrint('[FirmwareService] Failed to download firmware: ${firmware.fileName}');
    }
  }
}
