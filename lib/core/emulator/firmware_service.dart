import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/emulator/bios_registry.dart';
import 'package:freegosy/core/emulator/retroarch_core_list.dart';

typedef FirmwareProgressCallback = void Function(String fileName, int received, int total);

/// Describes the status of a single BIOS file on the local filesystem.
enum BiosFileStatus {
  /// File is present and MD5 matches (if hash available).
  valid,

  /// File is present but MD5 does not match — likely wrong version or corrupted.
  mismatch,

  /// File is present, no hash to verify against — assumed OK.
  present,

  /// File is not present on disk.
  missing,

  /// This BIOS file is not needed (HLE core or no registry entry).
  notNeeded,
}

class BiosFileInfo {
  final BiosFileSpec spec;
  final BiosFileStatus status;
  final String? actualPath;

  const BiosFileInfo({required this.spec, required this.status, this.actualPath});
}

class FirmwareService {
  final RommService _rommService;
  final DirectoryService _directoryService;
  final StrategyRegistry _strategyRegistry;

  FirmwareService(this._rommService, this._directoryService, this._strategyRegistry);

  /// Resolves the BIOS spec for an emulator + platform combination.
  ///
  /// For standalone emulators (Flycast, DuckStation, PCSX2, etc.) the registry
  /// key matches the emulatorId directly. For RetroArch, the key is the
  /// libretro core name without the `_libretro` suffix (e.g. `flycast` for
  /// `flycast_libretro`), so we resolve via the default core for the platform.
  EmulatorBiosSpec? _resolveBiosSpec(String emulatorId, String platformSlug) {
    // 1. Try the emulatorId directly (works for standalone emulators)
    final direct = getBiosSpecForEmulator(emulatorId);
    if (direct != null) return direct;

    // 2. For RetroArch, resolve via the default core for this platform
    if (emulatorId == 'retroarch') {
      final coreId = getDefaultCoreForSlug(platformSlug);
      if (coreId != null) {
        // Registry keys use the core name without _libretro suffix
        final registryKey = coreId.replaceAll('_libretro', '');
        final coreSpec = getBiosSpecForEmulator(registryKey);
        if (coreSpec != null) return coreSpec;
      }
    }

    return null;
  }

  /// Downloads all available firmware for all platforms and places them in the appropriate emulator BIOS directories.
  Future<void> syncAllFirmware({FirmwareProgressCallback? onProgress}) async {
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
        final biosSpec = _resolveBiosSpec(strategy.emulatorId, platform.slug);

        for (final firmware in platform.firmware) {
          await _downloadAndPlaceFirmware(firmware, biosDir, emulatorId: strategy.emulatorId, biosSpec: biosSpec, onProgress: onProgress);
        }
      }
    } catch (e) {
      debugPrint('[FirmwareService] Error syncing firmware: $e');
    }
  }

  /// Downloads firmware for a specific platform and places it in the emulator's BIOS directory.
  Future<void> syncFirmwareForPlatform(String platformSlug, {FirmwareProgressCallback? onProgress}) async {
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
      final biosSpec = _resolveBiosSpec(strategy.emulatorId, platform.slug);

      for (final firmware in platform.firmware) {
        await _downloadAndPlaceFirmware(firmware, biosDir, emulatorId: strategy.emulatorId, biosSpec: biosSpec, onProgress: onProgress);
      }
    } catch (e) {
      debugPrint('[FirmwareService] Error syncing firmware for $platformSlug: $e');
    }
  }

  /// Downloads firmware for a specific emulator and places it in its BIOS directory.
  Future<void> syncFirmwareForEmulator(String emulatorId, {FirmwareProgressCallback? onProgress}) async {
      debugPrint("[Firmware] Started individual emulator BIOS sync for $emulatorId");
    try {
      final platforms = await _rommService.getPlatforms();
      final biosDir = await _directoryService.getEmulatorBiosDirectory(emulatorId);
      final emuSupportedSlugs = _strategyRegistry.getStrategyById(emulatorId)?.supportedSlugs;

      for (final platform in platforms) {
          if (!emuSupportedSlugs!.contains(platform.slug) | platform.firmware.isEmpty) continue;
          final biosSpec = _resolveBiosSpec(emulatorId, platform.slug);
          for (final firmware in platform.firmware) {
            await _downloadAndPlaceFirmware(firmware, biosDir, emulatorId: emulatorId, biosSpec: biosSpec, onProgress: onProgress);
          }
      }
    } catch (e) {
      debugPrint('[FirmwareService] Error syncing firmware for emulator $emulatorId: $e');
    }
  }

  /// Checks the current BIOS status for an emulator.
  ///
  /// Returns a list of [BiosFileInfo] for each known BIOS file spec,
  /// with the current on-disk status.
  Future<List<BiosFileInfo>> checkBiosStatus(String emulatorId) async {
    final biosSpec = getBiosSpecForEmulator(emulatorId);
    if (biosSpec == null || biosSpec.files.isEmpty) return [];

    final biosDir = await _directoryService.getEmulatorBiosDirectory(emulatorId);
    final results = <BiosFileInfo>[];

    for (final spec in biosSpec.files) {
      // Resolve the actual path considering subdirectory
      final relativePath = spec.subdirectory != null
          ? p.join(spec.subdirectory!, spec.fileName)
          : spec.fileName;
      final filePath = p.join(biosDir, relativePath);
      final file = File(filePath);

      if (!await file.exists()) {
        results.add(BiosFileInfo(spec: spec, status: BiosFileStatus.missing));
        continue;
      }

      // If we have a known MD5 hash, verify it
      if (spec.md5Hash != null) {
        try {
          final bytes = await file.readAsBytes();
          final digest = md5.convert(bytes).toString();
          if (digest.toLowerCase() == spec.md5Hash!.toLowerCase()) {
            results.add(BiosFileInfo(spec: spec, status: BiosFileStatus.valid, actualPath: filePath));
          } else {
            results.add(BiosFileInfo(spec: spec, status: BiosFileStatus.mismatch, actualPath: filePath));
          }
        } catch (_) {
          // If we can't read the file, report it as present (unverifiable)
          results.add(BiosFileInfo(spec: spec, status: BiosFileStatus.present, actualPath: filePath));
        }
      } else {
        results.add(BiosFileInfo(spec: spec, status: BiosFileStatus.present, actualPath: filePath));
      }
    }

    return results;
  }

  Future<void> _downloadAndPlaceFirmware(
    Firmware firmware,
    String biosDir, {
    String? emulatorId,
    EmulatorBiosSpec? biosSpec,
    FirmwareProgressCallback? onProgress,
  }) async {
    debugPrint('[Firmware] firmware.fileName=${firmware.fileName}, firmware.filePath=${firmware.filePath}');

    // Determine the correct subdirectory from the BIOS registry, NOT from
    // RomM's filePath (which is just its internal storage path like "ps2/bios").
    // The registry knows where each emulator actually expects its BIOS files:
    //   - Flycast: subdirectory "dc" → system/dc/dc_boot.bin
    //   - Most others: null → system/SCPH1001.BIN (flat, at root)
    final matchingSpecForPath = _findMatchingSpec(firmware.fileName, biosSpec);
    final String relativePath;

    // 1. First check, are we syncing BIOS for RetroArch? If yes, we use the Libretro fallback subfolder for this core, if it exists in the registry.
    if (emulatorId == 'retroarch' && biosSpec?.fallbackSubdirectoryLibretro != null) {
      relativePath = p.join(biosSpec!.fallbackSubdirectoryLibretro!, firmware.fileName);
    // 2. Else, let's check if we recognize the filename of this Firmware. If there's a subfolder in the registry for this specific firmware, let's use it.
    } else if (matchingSpecForPath?.subdirectory != null) {
      relativePath = p.join(matchingSpecForPath!.subdirectory!, firmware.fileName);
    // 3. Else, we check if the registry contains a fallback subfolder for this standalone emulator.
    } else if (biosSpec?.fallbackSubdirectory != null) {
      relativePath = p.join(biosSpec!.fallbackSubdirectory!, firmware.fileName);
    // 4. If all else fails, simply put the firmware in the emulator's root folder.
    } else {
      relativePath = firmware.fileName;
    }

    final destPath = p.join(biosDir, relativePath);
    final destFile = File(destPath);
    debugPrint('[Firmware] relativePath=$relativePath, destPath=$destPath');

    if (await destFile.exists()) {
      // If we have a registry entry with a known MD5, verify the existing file
      final matchingSpec = _findMatchingSpec(firmware.fileName, biosSpec);
      if (matchingSpec?.md5Hash != null) {
        try {
          final bytes = await destFile.readAsBytes();
          final digest = md5.convert(bytes).toString();
          if (digest.toLowerCase() == matchingSpec!.md5Hash!.toLowerCase()) {
            debugPrint('[Firmware] File exists and MD5 matches, skipping: $destPath');
            return;
          } else {
            debugPrint('[Firmware] File exists but MD5 mismatch! Expected ${matchingSpec.md5Hash}, got $digest. Overwriting: $destPath');
            // Fall through to re-download
          }
        } catch (e) {
          debugPrint('[Firmware] Could not verify MD5 for $destPath: $e, skipping');
          return;
        }
      } else {
        debugPrint('[Firmware] File already exists (no hash to verify), skipping: $destPath');
        return;
      }
    }

    // Initial progress report
    onProgress?.call(firmware.fileName, 0, firmware.fileSizeBytes);

    final bytes = await _rommService.downloadFirmware(
      firmware, 
      onProgress: (received, total) {
        onProgress?.call(firmware.fileName, received, total);
      }
    );

    if (bytes != null) {
      await destFile.parent.create(recursive: true);
      await destFile.writeAsBytes(bytes);
      debugPrint('[Firmware] Wrote ${bytes.length} bytes to $destPath');

      // Post-download MD5 verification if we have a known hash
      final matchingSpec = _findMatchingSpec(firmware.fileName, biosSpec);
      if (matchingSpec?.md5Hash != null) {
        try {
          final digest = md5.convert(bytes).toString();
          if (digest.toLowerCase() != matchingSpec!.md5Hash!.toLowerCase()) {
            debugPrint('[Firmware] WARNING: Downloaded file MD5 mismatch! Expected ${matchingSpec.md5Hash}, got $digest');
          }
        } catch (_) {}
      }
    } else {
      debugPrint('[Firmware] Download returned null bytes for ${firmware.fileName}');
    }
  }

  /// Find a matching BIOS spec for a given filename.
  BiosFileSpec? _findMatchingSpec(String fileName, EmulatorBiosSpec? biosSpec) {
    if (biosSpec == null) return null;
    try {
      return biosSpec.files.firstWhere(
        (spec) => spec.fileName.toLowerCase() == fileName.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }
}
