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
  final bool isRemoved;

  RomSyncResult(this.path, this.romId, {this.game, this.isRemoved = false});
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

    bool forceFullScan = mappings.length < 10 && platformDirs.length > 5;

    if (dirtyDirs.isEmpty && !forceFullScan) {
      debugPrint('[RomScanner] No platform directories changed. Skipping scan.');
      return;
    }

    final dirsToScan = forceFullScan ? platformDirs : dirtyDirs;
    debugPrint('[RomScanner] Scanning ${dirsToScan.length} directories (Force: $forceFullScan)...');

    final List<String> dirPaths = dirsToScan.map((d) => d.path).toList();
    final List<String> scannedFiles = await compute(_performIsolatedScan, dirPaths);

    final Set<String> existingMappedFiles = mappings.keys.toSet();

    final List<String> newFiles = scannedFiles.where((f) => !existingMappedFiles.contains(f)).toList();
    
    // 1. Identify and yield REMOVALS immediately
    final List<String> removedFiles = [];
    final List<String> normalizedScannedPaths = scannedFiles.map((f) => p.normalize(f)).toList();
    final Set<String> normalizedScannedSet = normalizedScannedPaths.toSet();

    for (final mappedPath in existingMappedFiles) {
      final normalizedMappedPath = p.normalize(mappedPath);
      
      // Check if this mapped path is inside any of the directories we scanned
      bool isInsideScannedDir = false;
      for (final dir in dirsToScan) {
        final normalizedDir = p.normalize(dir.path);
        if (p.isWithin(normalizedDir, normalizedMappedPath) || normalizedDir == normalizedMappedPath) {
          isInsideScannedDir = true;
          break;
        }
      }

      if (isInsideScannedDir && !normalizedScannedSet.contains(normalizedMappedPath)) {
        removedFiles.add(mappedPath);
      }
    }

    if (removedFiles.isNotEmpty) {
      debugPrint('[RomScanner] Cleaning up ${removedFiles.length} removed files...');
      for (final f in removedFiles) {
        final romId = mappings[f];
        await _mappingService.removeMapping(f);
        if (romId != null) {
          yield RomSyncResult(f, romId, isRemoved: true);
        }
      }
    }

    if (newFiles.isEmpty) {
      debugPrint('[RomScanner] No new files found.');
      for (final dir in dirsToScan) {
        final stat = await dir.stat();
        await _mappingService.updateMTime(dir.path, stat.modified.millisecondsSinceEpoch);
      }
      return;
    }

    debugPrint('[RomScanner] Matching ${newFiles.length} new files...');

    const int maxConcurrent = 5;
    for (int i = 0; i < newFiles.length; i += maxConcurrent) {
      // PERF FIX: Add a tiny pause between batches to reduce system load spikes
      if (i > 0) await Future.delayed(const Duration(milliseconds: 100));

      final chunk = newFiles.sublist(i, i + maxConcurrent > newFiles.length ? newFiles.length : i + maxConcurrent);
      
      final results = await Future.wait(chunk.map((filePath) async {
        final fileName = p.basename(filePath);
        try {
          // Try 1: Exact filename match (safest)
          var searchResult = await _rommService.searchRoms(search: fileName);
          if (searchResult.isNotEmpty) {
            final game = searchResult.first;
            await _mappingService.updateMapping(filePath, game.id);
            return RomSyncResult(filePath, game.id, game: game);
          }

          // Try 2: SAFE FALLBACK - Strip extension
          // This helps with titles like "Marvel: Ultimate Alliance" where the file is "Marvel Ultimate Alliance.cso"
          final nameWithoutExt = p.basenameWithoutExtension(fileName).trim();
          if (nameWithoutExt.isNotEmpty && nameWithoutExt != fileName) {
            debugPrint('[RomScanner] Exact match failed, trying without extension: $nameWithoutExt');
            searchResult = await _rommService.searchRoms(search: nameWithoutExt);
            if (searchResult.isNotEmpty) {
              final game = searchResult.first;
              await _mappingService.updateMapping(filePath, game.id);
              return RomSyncResult(filePath, game.id, game: game);
            }
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
