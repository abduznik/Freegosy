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

      debugPrint('[RomScanner] Syncing platform: $platformSlug (File-Centric)...');
      
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
        
        // Skip hidden files, system files, etc.
        if (fileName.startsWith('.') || fileName.toLowerCase() == 'roms' || fileName.toLowerCase() == 'gamelist.xml') continue;

        debugPrint('[Scanner] Searching cloud for: $fileName');
        
        Game? matchedGame;
        
        // A. Direct Search by FileName
        try {
          final results = await _rommService.searchRoms(search: fileName, platformId: platformId);
          // Look for an exact match in filenames
          matchedGame = results.cast<Game?>().firstWhere(
            (g) => g?.fileName == fileName || g?.fsName == fileName,
            orElse: () => null,
          );

          // B. If it's a folder (PS3/Switch), try searching by its largest internal file
          if (matchedGame == null && await Directory(entityPath).exists()) {
             final subFiles = await Directory(entityPath).list(recursive: true).where((e) => e is File).cast<File>().toList();
             if (subFiles.isNotEmpty) {
               // Sort by size descending
               subFiles.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
               final largestFile = subFiles.first;
               final subFileName = p.basename(largestFile.path);
               
               debugPrint('[Scanner] Folder detection: searching for internal file $subFileName');
               final subResults = await _rommService.searchRoms(search: subFileName, platformId: platformId);
               matchedGame = subResults.cast<Game?>().firstWhere(
                 (g) => g?.fileName == subFileName || g?.fsName == subFileName,
                 orElse: () => null,
               );
             }
          }

          // C. Strict Name Match as last resort
          if (matchedGame == null) {
            final fileNameNoExt = p.basenameWithoutExtension(entityPath).toLowerCase();
            final fNameClean = _cleanName(fileNameNoExt);
            if (fNameClean.length > 3) {
              // We reuse the results from search(fileName) or do a new search if necessary
              final candidates = results.where((g) {
                if (_cleanName(g.name) == fNameClean) return true;
                final gFileNoExt = p.basenameWithoutExtension(g.fileName ?? '').toLowerCase();
                return _cleanName(gFileNoExt) == fNameClean;
              }).toList();

              if (candidates.length == 1) {
                final candidate = candidates.first;
                final localSize = index.fileSizes[entityPath] ?? (romsIndex?.fileSizes[entityPath] ?? 0);
                if (candidate.fileSize > 0 && localSize > 0) {
                  final diff = (candidate.fileSize - localSize).abs();
                  if (diff < 1024 * 1024 * 10) matchedGame = candidate;
                } else {
                  matchedGame = candidate;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[Scanner] Error searching for $fileName: $e');
        }

        if (matchedGame != null) {
          debugPrint('[Scanner] Locked: $fileName -> ${matchedGame.name} (ID: ${matchedGame.id})');
          await _mappingService.updateMapping(entityPath, matchedGame.id);
          matchedPathsInThisPlatform.add(entityPath);
          yield RomSyncResult(entityPath, matchedGame.id, game: matchedGame);
        } else {
          debugPrint('[Scanner] No cloud match for: $fileName');
        }
        
        // Small delay to avoid hammering the API if there are many files
        await Future.delayed(const Duration(milliseconds: 50));
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

  /// Clean a name for fuzzy matching by removing tags in [] or () and special characters
  String _cleanName(String name) {
    return name.toLowerCase()
        .replaceAll(RegExp(r'[\(\[][^\]\)]*[\)\]]'), ' ') // Remove content inside () or []
        .replaceAll(RegExp(r'[:-]'), ' ') // Explicitly handle dashes and colons as spaces
        .replaceAll(RegExp(r'[<>:"/\\|?*!\(\)\[\]]'), ' ') // Remove other special chars
        .replaceAll(RegExp(r'\s+'), ' ') // Collapse spaces
        .trim();
  }
}
