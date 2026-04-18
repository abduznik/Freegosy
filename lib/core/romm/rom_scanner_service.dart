import 'dart:io';
import 'dart:isolate';
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

    // Phase 2: Identify new/removed files in dirty directories using an Isolate
    final List<String> dirPaths = dirtyDirs.map((d) => d.path).toList();
    final List<String> allFiles = await Isolate.run(() => _scanDirectories(dirPaths));

    // Phase 3: Update mtimes for scanned directories
    final Map<String, int> newMTimes = Map.from(storedMTimes);
    for (final dir in dirtyDirs) {
      final stat = await dir.stat();
      newMTimes[dir.path] = stat.modified.millisecondsSinceEpoch;
    }
    await _mappingService.saveMTimes(newMTimes);

    final Set<String> existingFiles = mappings.keys.toSet();
    final Set<String> currentFilesSet = allFiles.toSet();

    // Identify truly new files
    final List<String> newFiles = allFiles.where((f) => !existingFiles.contains(f)).toList();
    
    // Clean up removed files from mappings
    final List<String> removedFiles = existingFiles.where((f) => !currentFilesSet.contains(f)).toList();
    if (removedFiles.isNotEmpty) {
      final updatedMappings = Map<String, String>.from(mappings);
      for (final f in removedFiles) {
        updatedMappings.remove(f);
      }
      await _mappingService.saveMappings(updatedMappings);
    }

    if (newFiles.isEmpty) {
      debugPrint('[RomScanner] No new files found in dirty directories.');
      return;
    }

    debugPrint('[RomScanner] Matching ${newFiles.length} new files...');

    // Phase 4: Match new files via RomM API
    for (final filePath in newFiles) {
      final fileName = p.basename(filePath);
      
      // Try filename match first (fast)
      final searchResult = await _rommService.searchRoms(search: fileName);
      if (searchResult.isNotEmpty) {
        final game = searchResult.first;
        await _mappingService.updateMapping(filePath, game.id);
        yield RomSyncResult(filePath, game.id, game: game);
        continue;
      }

      // Optional: SHA1 match (slower, could be triggered by user or done here)
      // For now, let's keep it simple and just yield the path if not found
      yield RomSyncResult(filePath, null);
    }
  }

  /// Calculates SHA1 for a file. Can be used for deep matching.
  static Future<String> calculateSha1(String path) async {
    final file = File(path);
    if (!await file.exists()) return '';
    final bytes = await file.readAsBytes();
    return sha1.convert(bytes).toString();
  }
}

/// Helper function to be run in an Isolate
List<String> _scanDirectories(List<String> paths) {
  final List<String> files = [];
  for (final path in paths) {
    final dir = Directory(path);
    if (dir.existsSync()) {
      // Shallow scan: only files in the directory
      // (Assuming ROMs/Platform/File structure)
      for (final entity in dir.listSync()) {
        if (entity is File) {
          files.add(entity.path);
        } else if (entity is Directory) {
           // Handle folders that are treated as games (e.g. Windows)
           files.add(entity.path);
        }
      }
    }
  }
  return files;
}
