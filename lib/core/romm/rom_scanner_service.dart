import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'romm_service.dart';
import '../storage/rom_mapping_service.dart';
import 'romm_models.dart';
import 'package:crypto/crypto.dart';

class RomSyncResult {
  final String path;
  final String? romId;
  final Game? game;

  RomSyncResult(this.path, this.romId, {this.game});
}

/// TOP-LEVEL function for compute() to avoid capturing 'this'
List<String> _performIsolatedScan(List<String> paths) {
  final List<String> files = [];
  for (final path in paths) {
    final dir = Directory(path);
    if (dir.existsSync()) {
      try {
        for (final entity in dir.listSync()) {
          files.add(entity.path);
        }
      } catch (_) {}
    }
  }
  return files;
}

class RomScannerService {
  final RommService _rommService;
  final RomMappingService _mappingService;

  RomScannerService(this._rommService, this._mappingService);

  /// Performs an incremental sync of the ROM directory.
  Stream<RomSyncResult> sync(String romsRoot) async* {
    final storedMTimes = _mappingService.getMTimes();
    final mappings = _mappingService.getMappings();
    
    final rootDir = Directory(romsRoot);
    if (!await rootDir.exists()) return;

    // Phase 1: Check platform directories for changes
    final List<Directory> platformDirs = [];
    await for (final entity in rootDir.list()) {
      if (entity is Directory) {
        platformDirs.add(entity);
      }
    }

    final List<Directory> dirtyDirs = [];
    for (final dir in platformDirs) {
      final storedMTime = storedMTimes[dir.path];
      final stat = await dir.stat();
      if (storedMTime != stat.modified.millisecondsSinceEpoch) {
        dirtyDirs.add(dir);
      }
    }

    if (dirtyDirs.isEmpty) {
      debugPrint('[RomScanner] No platform directories changed. Skipping scan.');
      return;
    }

    debugPrint('[RomScanner] Scanning ${dirtyDirs.length} dirty platform directories...');

    // Phase 2: Identify files using compute() with a TOP-LEVEL function.
    // This is safer than Isolate.run inside an instance method.
    final List<String> dirPaths = dirtyDirs.map((d) => d.path).toList();
    final List<String> allFiles = await compute(_performIsolatedScan, dirPaths);

    // Phase 3: Update mtimes for scanned directories
    for (final dir in dirtyDirs) {
      final stat = await dir.stat();
      await _mappingService.updateMTime(dir.path, stat.modified.millisecondsSinceEpoch);
    }

    final Set<String> existingFiles = mappings.keys.toSet();
    final Set<String> currentFilesSet = allFiles.toSet();

    // Identify truly new files
    final List<String> newFiles = allFiles.where((f) => !existingFiles.contains(f)).toList();
    
    // Clean up removed files from mappings
    final List<String> removedFiles = existingFiles.where((f) => !currentFilesSet.contains(f)).toList();
    if (removedFiles.isNotEmpty) {
      for (final f in removedFiles) {
        await _mappingService.removeMapping(f);
      }
    }

    if (newFiles.isEmpty) {
      debugPrint('[RomScanner] No new files found in dirty directories.');
      return;
    }

    debugPrint('[RomScanner] Matching ${newFiles.length} new files...');

    // Phase 4: Match new files via RomM API in parallel batches
    const int maxConcurrent = 5;
    for (int i = 0; i < newFiles.length; i += maxConcurrent) {
      final chunk = newFiles.sublist(i, i + maxConcurrent > newFiles.length ? newFiles.length : i + maxConcurrent);
      
      final results = await Future.wait(chunk.map((filePath) async {
        final fileName = p.basename(filePath);
        try {
          final searchResult = await _rommService.searchRoms(search: fileName);
          if (searchResult.isNotEmpty) {
            final game = searchResult.first;
            await _mappingService.updateMapping(filePath, game.id);
            return RomSyncResult(filePath, game.id, game: game);
          }
        } catch (e) {
          debugPrint('[RomScanner] Error matching $fileName: $e');
        }
        return RomSyncResult(filePath, null);
      }));

      for (final result in results) {
        yield result;
      }
    }
  }

  static Future<String> calculateSha1(String path) async {
    final file = File(path);
    if (!await file.exists()) return '';
    final bytes = await file.readAsBytes();
    return sha1.convert(bytes).toString();
  }
}
