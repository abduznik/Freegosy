import 'dart:io' as io;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

// ─── Strategy ────────────────────────────────────────────────────────────────

/// Save strategy for Azahar (Nintendo 3DS) emulator.
///
/// Follows the Eden pattern: requires manual folder mapping from the 'sdmc' 
/// directory if automatic resolution is not possible.
class AzaharSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;
  final Future<void> Function(String gameId, String mapping)? onMappingResolved;

  AzaharSaveStrategy(this._directoryService, {this.onMappingResolved});

  @override
  String get strategyId => '3ds';

  @override
  bool get supportsSaveSync => true;

  String? _manualMapping;

  /// Sets the manual mapping (relative path from sdmc directory).
  void setManualMapping(String? mapping) {
    _manualMapping = mapping;
  }

  Future<String> _getAzaharSystemBase({String? platformSlug}) async {
    final resolvedPath = await _directoryService.getEmulatorSystemDirectory('azahar', platformSlug: platformSlug);
    if (!await io.Directory(resolvedPath).exists()) {
      throw Exception('Save directory not found for Azahar at $resolvedPath. Please launch Azahar at least once to generate save data.');
    }
    return resolvedPath;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    if (_manualMapping == null || _manualMapping!.isEmpty) {
      debugPrint('[Azahar] FAILED: No manual mapping resolved for ${game.name}');
      throw SaveMappingRequiredException(
          'Could not determine save folder for "${game.name}". '
          'Please select the save folder manually from the sdmc directory.');
    }

    final base = await _getAzaharSystemBase(platformSlug: game.platformSlug);

    // _manualMapping is expected to be the relative path from sdmc
    final finalPath = p.join(base, 'sdmc', _manualMapping!);
    debugPrint('[Azahar] Final path: $finalPath');

    return finalPath;
  }

  @override
  Future<List<io.File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];

    final dir = io.Directory(saveDir);
    if (!dir.existsSync()) {
      if (syncMode == 'push') {
        throw Exception('Local save data not found for pushing.');
      }
      return [];
    }

    // Check if directory actually contains save files
    final hasFiles = dir.listSync(recursive: true).any((f) => f is io.File);
    if (!hasFiles) {
      if (syncMode == 'push') {
        throw Exception('Save directory exists but contains no save files.');
      }
      return [];
    }

    // If sessionStart filter is set, check if any file was modified after it
    if (sessionStart != null) {
      final files = dir.listSync(recursive: true).whereType<io.File>();
      final hasChanges = files.any((f) => f.statSync().modified.isAfter(sessionStart));
      if (!hasChanges) {
        debugPrint('[Azahar] No files modified since session start');
        return [];
      }
    }

    // Return the DIRECTORY as a File reference.
    // SaveSyncService.pushSaves() detects isDirectory and zips it.
    return [io.File(saveDir)];
  }

  @override
  Future<bool> restoreSave(
    Game game,
    String destPath,
    Uint8List data,
    String filename,
  ) async {
    try {
      debugPrint('=== AZAHAR RESTORE: ${game.name} ===');
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) return false;

      final dir = io.Directory(saveDir);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        return await _extractArchive(archive, saveDir);
      } else {
        final filePath = p.join(saveDir, filename);
        await backupSave(filePath);
        await io.File(filePath).writeAsBytes(data);
        debugPrint('[Azahar][Restore] Wrote single file: $filePath');
        return true;
      }
    } catch (e) {
      if (e is SaveMappingRequiredException) {
        rethrow;
      }
      debugPrint('[Azahar][Restore] ERROR: $e');
      return false;
    }
  }

  /// Extracts a ZIP archive into [destDir], stripping a leading folder if present.
  Future<bool> _extractArchive(Archive archive, String destDir) async {
    try {
      for (final entry in archive) {
        if (entry.name.isEmpty) continue;

        // Strip leading folder if present (e.g. "00000001/save.bin" -> "save.bin")
        final segments = entry.name.split(RegExp(r'[/\\]'));
        final entryPath = (segments.length > 1)
            ? p.joinAll(segments.sublist(1))
            : entry.name;

        if (entryPath.isEmpty) continue;

        final outPath = p.join(destDir, entryPath);
        if (entry.isFile) {
          await backupSave(outPath);
          final outFile = io.File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
          debugPrint('[Azahar][Extract] ${entry.name} → $outPath');
        } else {
          await io.Directory(outPath).create(recursive: true);
        }
      }
      return true;
    } catch (e) {
      debugPrint('[Azahar][Extract] ERROR: $e');
      return false;
    }
  }

  /// Scans the 'sdmc' directory for available save data folders.
  /// Looks for '00000001' folders which are typical for 3DS saves.
  Future<List<Map<String, dynamic>>> getAvailableSaveFolders() async {
    final base = await _getAzaharSystemBase();

    final sdmcDir = io.Directory(p.join(base, 'sdmc'));
    if (!sdmcDir.existsSync()) {
      debugPrint('[Azahar] sdmc directory not found at: ${sdmcDir.path}');
      return [];
    }

    final folders = <Map<String, dynamic>>[];
    final hex16Regex = RegExp(r'^[0-9A-Fa-f]{16}$');
    
    try {
      await for (final entity in sdmcDir.list(recursive: true, followLinks: false)) {
        if (entity is io.Directory) {
          final name = p.basename(entity.path);
          if (name == '00000001') {
            // It's a save data folder
            DateTime? newest;
            int fileCount = 0;
            
            try {
              for (final f in entity.listSync(recursive: true)) {
                if (f is! io.File) continue;
                final fname = p.basename(f.path);
                if (fname.startsWith('.') || fname.endsWith('.bak')) continue;

                fileCount++;
                final stat = f.statSync();
                if (newest == null || stat.modified.isAfter(newest)) {
                  newest = stat.modified;
                }
              }
            } catch (_) {}

            if (fileCount > 0) {
              final relativePath = p.relative(entity.path, from: sdmcDir.path);
              
              // Try to find a Title ID in the path (typically 16-hex)
              String displayName = relativePath;
              final segments = p.split(relativePath);
              for (int i = segments.length - 1; i >= 0; i--) {
                if (segments[i].length == 16 && hex16Regex.hasMatch(segments[i])) {
                  displayName = segments[i];
                  break;
                }
              }

              folders.add({
                'name': displayName,
                'path': relativePath,
                'lastModified': newest ?? entity.statSync().modified,
                'fileCount': fileCount,
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Azahar] Error scanning folders: $e');
    }

    folders.sort((a, b) => (b['lastModified'] as DateTime)
        .compareTo(a['lastModified'] as DateTime));
    return folders;
  }
}
