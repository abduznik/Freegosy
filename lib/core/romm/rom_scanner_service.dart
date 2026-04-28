import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'romm_service.dart';
import '../storage/rom_mapping_service.dart';
import 'romm_models.dart';
import 'package:crypto/crypto.dart';
import '../storage/directory_service.dart';

class RomSyncResult {
  final String path;
  final String? romId;
  final Game? game;
  final bool isRemoved;

  RomSyncResult(this.path, this.romId, {this.game, this.isRemoved = false});
}



class RomScannerService {
  final RommService _rommService;
  final RomMappingService _mappingService;
  final DirectoryService _directoryService;

  RomScannerService(this._rommService, this._mappingService, this._directoryService);

  /// Performs an incremental sync of the ROM directory.
  /// Performs a high-performance file-centric sync of the ROM directory.
  Stream<RomSyncResult> sync(String romsRoot, {bool force = false}) async* {
    final mappings = _mappingService.getMappings();
    final rootDir = Directory(romsRoot);
    if (!await rootDir.exists()) return;

    // 0. Fetch platforms to map slugs to IDs
    final platforms = await _rommService.getPlatforms();
    final platformSlugToId = {for (var p in platforms) p.slug.toLowerCase(): p.id.toString()};

    final List<Directory> platformDirs = [];
    await for (final entity in rootDir.list()) {
      if (entity is Directory) platformDirs.add(entity);
    }

    final storedMTimes = _mappingService.getMTimes();
    for (final dir in platformDirs) {
      final platformSlug = p.basename(dir.path).toLowerCase();
      final platformId = platformSlugToId[platformSlug];
      if (platformId == null) continue;

      final stat = await dir.stat();
      final storedMTime = storedMTimes[dir.path];
      
      // If not forced and mtime matches, skip if we already have some mappings for this platform
      if (!force && storedMTime == stat.modified.millisecondsSinceEpoch && mappings.values.any((id) => mappings.entries.any((e) => p.isWithin(dir.path, e.key)))) {
        continue;
      }

      debugPrint('[Scan] $platformSlug...');
      
      // 1. Build local indices (ls)
      final index = await FileSystemIndex.build(dir.path);
      final romsSubDir = p.join(dir.path, 'roms');
      FileSystemIndex? romsIndex;
      if (await Directory(romsSubDir).exists()) {
        romsIndex = await FileSystemIndex.build(romsSubDir);
      }

      final Set<String> matchedPathsInThisPlatform = {};
      final List<String> localEntities = [...index.files.values, ...index.dirs.values];
      if (romsIndex != null) {
        localEntities.addAll([...romsIndex.files.values, ...romsIndex.dirs.values]);
      }

      // --- PASS 1: VERIFY EXISTING MAPPINGS ---
      final platformMappings = mappings.entries.where((e) => p.isWithin(dir.path, e.key)).toList();
      for (final entry in platformMappings) {
        if (await File(entry.key).exists() || await Directory(entry.key).exists()) {
          matchedPathsInThisPlatform.add(entry.key);
        } else {
          debugPrint('[Scanner] Removing stale mapping: ${entry.key}');
          await _mappingService.removeMapping(entry.key);
          yield RomSyncResult(entry.key, entry.value, isRemoved: true);
        }
      }

      // --- PASS 2: TARGETED DISCOVERY (Local -> Cloud) ---
      for (final entityPath in localEntities) {
        if (matchedPathsInThisPlatform.contains(entityPath)) continue;

        final fileName = p.basename(entityPath);
        
        // Skip hidden files, system files, known non-rom files, and files with invalid extensions
        if (fileName.startsWith('.') || 
            fileName.toLowerCase() == 'roms' || 
            fileName.toLowerCase() == 'gamelist.xml' ||
            fileName.toLowerCase().endsWith('.sav') ||
            fileName.toLowerCase().endsWith('.srm') ||
            fileName.toLowerCase().endsWith('.txt') ||
            fileName.toLowerCase().endsWith('.pdf') ||
            fileName.toLowerCase().endsWith('.jpg') ||
            fileName.toLowerCase().endsWith('.png')) {
          continue;
        }

        // Strict extension validation
        if (await File(entityPath).exists() && !DirectoryService.isRomFile(platformSlug, entityPath)) {
          debugPrint('[Scanner] Skipping non-ROM file by extension: $fileName');
          continue;
        }

        debugPrint('[Scan] ? $fileName');
        
        // Extract key search term (First 1-2 words, at least 3 chars)
        final words = fileName.split(RegExp(r'[\s\.\-_\[\(]')).where((w) => w.length >= 3).toList();
        final searchTerm = words.take(2).join(' ');
        
        if (searchTerm.isEmpty) {
          debugPrint('[Scanner] Skipping file with no searchable name: $fileName');
          continue;
        }

        debugPrint('[Scan] Search: "$searchTerm"');
        
        Game? matchedGame;
        
        try {
          final results = await _rommService.searchRoms(search: searchTerm, platformId: platformId);
          // debugPrint('[Scanner] Cloud returned ${results.length} candidates for "$searchTerm"');

          for (final candidate in results) {
            // VERIFICATION: Use the exact same robust logic the Detail Card uses
            final confirmedPath = await _directoryService.findExistingRomPath(candidate, index: index);
            
            if (confirmedPath != null && p.canonicalize(confirmedPath) == p.canonicalize(entityPath)) {
              matchedGame = candidate;
              break; 
            }
            
            // Fallback: If DirectoryService didn't find it (e.g. extension issue), check for direct filename match
            if (candidate.fileName == fileName || candidate.fsName == fileName) {
              matchedGame = candidate;
              break;
            }
          }
        } catch (e) {
          debugPrint('[Scanner] Error searching for $fileName: $e');
        }

        if (matchedGame != null) {
          debugPrint('[Scan] Found: $fileName -> ${matchedGame.name}');
          await _mappingService.updateMapping(entityPath, matchedGame.id);
          matchedPathsInThisPlatform.add(entityPath);
          yield RomSyncResult(entityPath, matchedGame.id, game: matchedGame);
        } else {
          // debugPrint('[Scanner] No cloud match for: $fileName');
        }
        
        // Small delay to avoid hammering the API
        await Future.delayed(const Duration(milliseconds: 100));
      }

      await _mappingService.updateMTime(dir.path, stat.modified.millisecondsSinceEpoch);
    }
  }

  static Future<String> calculateSha1(String path) async {
    final file = File(path);
    if (!await file.exists()) return '';
    final bytes = await file.readAsBytes();
    return sha1.convert(bytes).toString();
  }

  /// Targeted sync for a single game. Useful for "Lazy Sync" on Detail screen.
  Future<void> syncSingleGame(Game game) async {
    final mappings = _mappingService.getMappings();
    
    // Check if we already have a mapping for this game ID
    final existingPath = mappings.entries.where((e) => e.value == game.id).map((e) => e.key).firstOrNull;
    
    if (existingPath != null) {
      // Verify if the file still exists
      if (await File(existingPath).exists() || await Directory(existingPath).exists()) {
        debugPrint('[RomScanner] Single Sync: ${game.name} already correctly mapped.');
        return;
      } else {
        debugPrint('[RomScanner] Single Sync: ${game.name} was mapped to missing file. Removing.');
        await _mappingService.removeMapping(existingPath);
      }
    }

    // Try to find the game on disk using DirectoryService's robust logic
    final foundPath = await _directoryService.findExistingRomPath(game);
    if (foundPath != null) {
      debugPrint('[RomScanner] Single Sync REPAIR: Found ${game.name} at $foundPath');
      await _mappingService.updateMapping(foundPath, game.id);
    } else {
      debugPrint('[RomScanner] Single Sync: ${game.name} not found on disk.');
    }
  }


  /// Prunes all mappings that point to non-existent files.
  Future<int> pruneDeadMappings() async {
    final mappings = _mappingService.getMappings();
    int count = 0;
    for (final entry in mappings.entries) {
      if (!await File(entry.key).exists() && !await Directory(entry.key).exists()) {
        await _mappingService.removeMapping(entry.key);
        count++;
      }
    }
    return count;
  }
}
