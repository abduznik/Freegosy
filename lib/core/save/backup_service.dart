import 'dart:io' as io;
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../romm/romm_models.dart';
import 'romm_content_hash.dart';
import 'save_sync_service.dart';
import 'strategies/retroarch_save_strategy.dart';

/// Result record returned by [BackupService.createImmediate].
/// [coreId]: the RetroArch core whose folder was backed up; null otherwise.
typedef BackupResult = ({String zipPath, String md5, String? coreId});

/// Handles creating and restoring local save-file backups.
///
/// Reuses the same [ZipFileEncoder] pipeline already used by
/// [SaveSyncService.pushSaves] — no new compression mechanism is introduced.
class BackupService {
  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Creates an immediate restore-point ZIP for [game].
  ///
  /// Returns a [BackupResult] with the path to the written ZIP and its MD5
  /// hash, or `null` if no save files are found (nothing to back up).
  ///
  /// [emulatorId] should be the emulator that actually launched the game
  /// this session, if known — otherwise this can silently back up a
  /// different emulator's (stale, unrelated) save file when the platform's
  /// globally-configured preference differs from what was actually used
  /// (same root cause as issue #79, but for the post-exit backup step).
  Future<BackupResult?> createImmediate(
    Game game,
    String romPath,
    SaveSyncService syncService, {
    String? emulatorId,
    String? coreOverride,
  }) async {
    try {
      // Gather current save files using the same strategy already used for
      // cloud sync, set up for this game (RetroArch: [coreOverride]'s folder).
      final found = await syncService.withStrategy(
          game,
          (strategy) async => (
                files: await strategy.getSaveFiles(game, romPath),
                core: strategy is RetroArchSaveStrategy ? strategy.coreIdFor(game) : null,
              ),
          emulatorId: emulatorId,
          coreOverride: coreOverride);
      final files = found?.files ?? const <io.File>[];
      if (files.isEmpty) return null;

      final backupsDir = await _backupsDirectory();
      final tempDir = io.Directory(p.join(backupsDir.path, '.tmp'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      // Build ZIP using the exact same ZipFileEncoder pipeline as SaveSyncService
      final tempZipPath = p.join(tempDir.path, '${game.id}_tmp_${DateTime.now().millisecondsSinceEpoch}.zip');
      final encoder = ZipFileEncoder();
      encoder.create(tempZipPath);

      for (final file in files) {
        if (await io.FileSystemEntity.isDirectory(file.path)) {
          await encoder.addDirectory(io.Directory(file.path), includeDirName: true);
        } else {
          await encoder.addFile(file, p.basename(file.path));
        }
      }
      encoder.close();

      // The hash of the files in the zip, not of the zip: an emulator that
      // rewrites an unchanged save gives new file times, not a new backup.
      final zipFile = io.File(tempZipPath);
      final bytes = await zipFile.readAsBytes();
      final digest = rommHashOfUpload(bytes) ?? md5.convert(bytes).toString();

      // Rename to final convention: freegosy_[romId]_[timestamp]_[md5].zip
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final finalName = 'freegosy_${game.id}_${timestamp}_$digest.zip';
      final finalPath = p.join(backupsDir.path, finalName);
      await zipFile.rename(finalPath);

      debugPrint('[BackupService] Created backup: $finalName');
      return (zipPath: finalPath, md5: digest, coreId: found?.core);
    } catch (e) {
      debugPrint('[BackupService] createImmediate error: $e');
      return null;
    }
  }

  /// Restores save files from a local backup [entry] by extracting its ZIP
  /// back into the emulator's save directory: [emulatorId]'s when given,
  /// else the game's emulator as save sync resolves it.
  ///
  /// Before restoring, the caller should call [createImmediate] to snapshot
  /// the current state as a safety copy.
  Future<bool> restore(
    String localZipPath,
    Game game,
    String romPath,
    SaveSyncService syncService, {
    String? emulatorId,
    String? coreOverride,
  }) async {
    try {
      final zipFile = io.File(localZipPath);
      if (!await zipFile.exists()) return false;
      final bytes = await zipFile.readAsBytes();
      // The strategy puts it back: a save file other games share (a memory
      // card) gets only this game's saves from it.
      final ok = await syncService.withStrategy(
              game, (strategy) => strategy.restoreBackup(game, romPath, bytes, p.basename(localZipPath)),
              emulatorId: emulatorId, coreOverride: coreOverride) ??
          false;
      debugPrint('[BackupService] Restored from: $localZipPath (ok=$ok)');
      return ok;
    } catch (e) {
      debugPrint('[BackupService] restore error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Returns (and creates if needed) the per-app backups directory.
  Future<io.Directory> _backupsDirectory() async {
    final appSupport = await getApplicationSupportDirectory();
    final dir = io.Directory(p.join(appSupport.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
