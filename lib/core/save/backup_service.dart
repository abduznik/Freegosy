import 'dart:io' as io;
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../romm/romm_models.dart';
import 'save_sync_service.dart';

/// Result record returned by [BackupService.createImmediate].
typedef BackupResult = ({String zipPath, String md5});

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
  Future<BackupResult?> createImmediate(
    Game game,
    String romPath,
    SaveSyncService syncService,
  ) async {
    try {
      final strategy = syncService.getStrategyForSlug(game.platformSlug);
      if (strategy == null) return null;

      // Gather current save files using the same strategy already used for cloud sync
      final files = await strategy.getSaveFiles(game, romPath);
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

      // Compute MD5 of the resulting ZIP
      final zipFile = io.File(tempZipPath);
      final bytes = await zipFile.readAsBytes();
      final digest = md5.convert(bytes).toString();

      // Rename to final convention: freegosy_[romId]_[timestamp]_[md5].zip
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final finalName = 'freegosy_${game.id}_${timestamp}_$digest.zip';
      final finalPath = p.join(backupsDir.path, finalName);
      await zipFile.rename(finalPath);

      debugPrint('[BackupService] Created backup: $finalName');
      return (zipPath: finalPath, md5: digest);
    } catch (e) {
      debugPrint('[BackupService] createImmediate error: $e');
      return null;
    }
  }

  /// Restores save files from a local backup [entry] by extracting its ZIP
  /// back into the emulator's save directory.
  ///
  /// Before restoring, the caller should call [createImmediate] to snapshot
  /// the current state as a safety copy.
  Future<bool> restore(
    String localZipPath,
    Game game,
    String romPath,
    SaveSyncService syncService,
  ) async {
    try {
      final strategy = syncService.getStrategyForSlug(game.platformSlug);
      if (strategy == null) return false;

      final saveDir = await strategy.getSaveDir(game, romPath);
      if (saveDir == null) return false;

      final zipFile = io.File(localZipPath);
      if (!await zipFile.exists()) return false;

      // Extract using archive package (same package already used in ExtractionService)
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final archiveFile in archive) {
        final filePath = p.join(saveDir, archiveFile.name);
        if (archiveFile.isFile) {
          final outFile = io.File(filePath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(archiveFile.content as List<int>);
        } else {
          await io.Directory(filePath).create(recursive: true);
        }
      }

      debugPrint('[BackupService] Restored from: $localZipPath → $saveDir');
      return true;
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
