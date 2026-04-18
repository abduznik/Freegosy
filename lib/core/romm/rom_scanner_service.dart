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

    // SAFETY CHECK: If mappings are very low but we have many platform dirs,
    // something went wrong (like the deletion bug). Force a scan.
    bool forceFullScan = mappings.length < 10 && platformDirs.length > 5;

    if (dirtyDirs.isEmpty && !forceFullScan) {
      debugPrint('[RomScanner] No platform directories changed. Skipping scan.');
      return;
    }

    final dirsToScan = forceFullScan ? platformDirs : dirtyDirs;
    debugPrint('[RomScanner] Scanning ${dirsToScan.length} directories (Force: $forceFullScan)...');

    final List<String> dirPaths = dirsToScan.map((d) => d.path).toList();
    final List<String> scannedFiles = await compute(_performIsolatedScan, dirPaths);

    final Set<String> scannedFilesSet = scannedFiles.toSet();
    final Set<String> existingMappedFiles = mappings.keys.toSet();

    // 1. Identify new files (scanned but not in existing mappings)
    final List<String> newFiles = scannedFiles.where((f) => !existingMappedFiles.contains(f)).toList();
    
    // 2. Identify removed files 
    // CRITICAL FIX: Only check for removal within the directories we ACTUALLY scanned.
    final List<String> removedFiles = [];
    for (final mappedPath in existingMappedFiles) {
      // If this file belongs to one of the scanned directories...
      bool isInScannedDir = dirsToScan.any((d) => mappedPath.startsWith(d.path));
      // ...and it's no longer there, it's truly removed.
      if (isInScannedDir && !scannedFilesSet.contains(mappedPath)) {
        removedFiles.add(mappedPath);
      }
    }

    if (removedFiles.isNotEmpty) {
      debugPrint('[RomScanner] Cleaning up ${removedFiles.length} removed files...');
      for (final f in removedFiles) {
        await _mappingService.removeMapping(f);
      }
    }

    if (newFiles.isEmpty) {
      debugPrint('[RomScanner] No new files found.');
      // Update mtimes even if no new files, as we've verified the state
      for (final dir in dirsToScan) {
        final stat = await dir.stat();
        await _mappingService.updateMTime(dir.path, stat.modified.millisecondsSinceEpoch);
      }
      return;
    }

    debugPrint('[RomScanner] Matching ${newFiles.length} new files...');

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

    // Phase 5: Update mtimes only AFTER successful matching
    for (final dir in dirsToScan) {
      final stat = await dir.stat();
      await _mappingService.updateMTime(dir.path, stat.modified.millisecondsSinceEpoch);
    }
  }

  static Future<String> calculateSha1(String path) async {
    final file = File(path);
    if (!await file.exists()) return '';
    final bytes = await file.readAsBytes();
    return sha1.convert(bytes).toString();
  }
}
