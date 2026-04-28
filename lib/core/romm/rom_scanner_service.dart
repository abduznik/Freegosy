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
    final mappings = _mappingService.getMappings();
    
    final rootDir = Directory(romsRoot);
    if (!await rootDir.exists()) return;

    // 0. Fetch platforms to map slugs to IDs
    final platforms = await _rommService.getPlatforms();
    final platformSlugToId = {for (var p in platforms) p.slug.toLowerCase(): p.id.toString()};

    final List<Directory> platformDirs = [];
    await for (final entity in rootDir.list()) {
      if (entity is Directory) {
        platformDirs.add(entity);
      }
    }

    final storedMTimes = _mappingService.getMTimes();
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
    debugPrint('[RomScanner] Scanning ${dirsToScan.length} directories...');

    for (final dir in dirsToScan) {
      final platformSlug = p.basename(dir.path).toLowerCase();
      final platformId = platformSlugToId[platformSlug];
      
      if (platformId == null) {
        debugPrint('[RomScanner] Skipping unknown platform folder: $platformSlug');
        continue;
      }

      debugPrint('[RomScanner] Processing $platformSlug (ID: $platformId)...');
      
      // 1. Fetch all games for this platform from RomM (Bulk fetch is much faster)
      final List<Game> platformGames = [];
      try {
        int offset = 0;
        const int batchSize = 250;
        while (true) {
          final result = await _rommService.getGamesPage(
            offset: offset, 
            limit: batchSize, 
            platformId: platformId
          );
          platformGames.addAll(result.games);
          if (platformGames.length >= result.total || result.games.isEmpty) break;
          offset += batchSize;
        }
      } catch (e) {
        debugPrint('[RomScanner] Error fetching platform games for $platformSlug: $e');
        continue;
      }

      // 2. Scan the directory
      final List<FileSystemEntity> entities = await dir.list().toList();
      final scannedFiles = entities.whereType<File>().toList();
      
      // 3. Match new files
      for (final file in scannedFiles) {
        final filePath = file.path;
        if (mappings.containsKey(filePath)) continue; // Already mapped

        final fileName = p.basename(filePath);
        final fileNameNoExt = p.basenameWithoutExtension(filePath).toLowerCase();
        
        Game? matchedGame;

        // MATCHING STRATEGY 1: Exact Filename match (Very Reliable)
        matchedGame = platformGames.cast<Game?>().firstWhere(
          (g) => g?.fileName == fileName || g?.fsName == fileName,
          orElse: () => null,
        );

        // MATCHING STRATEGY 2: Clean Name match
        if (matchedGame == null) {
          matchedGame = platformGames.cast<Game?>().firstWhere((g) {
            if (g == null) return false;
            final gName = g.name.toLowerCase().replaceAll(RegExp(r'[<>:"/\\|?*!\-\(\)\[\]]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
            final fName = fileNameNoExt.replaceAll(RegExp(r'[<>:"/\\|?*!\-\(\)\[\]]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
            return gName == fName;
          }, orElse: () => null);
        }

        if (matchedGame != null) {
          await _mappingService.updateMapping(filePath, matchedGame.id);
          yield RomSyncResult(filePath, matchedGame.id, game: matchedGame);
        } else {
          // If bulk match failed, try one last API search specifically for this file on this platform
          try {
            final results = await _rommService.searchRoms(search: fileName, platformId: platformId);
            if (results.isNotEmpty) {
              final game = results.first;
              await _mappingService.updateMapping(filePath, game.id);
              yield RomSyncResult(filePath, game.id, game: game);
            }
          } catch (_) {}
        }
      }

      // 4. Identify REMOVALS for this platform
      final Set<String> currentFiles = scannedFiles.map((f) => f.path).toSet();
      final platformMappings = mappings.entries.where((e) => p.isWithin(dir.path, e.key));
      
      for (final entry in platformMappings) {
        if (!currentFiles.contains(entry.key)) {
          await _mappingService.removeMapping(entry.key);
          yield RomSyncResult(entry.key, entry.value, isRemoved: true);
        }
      }

      // Update mtime to mark directory as synced
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
