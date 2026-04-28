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
      
      // 1. Fetch all games for this platform from RomM
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

      // 2. Build File System Index for this platform
      final index = await FileSystemIndex.build(dir.path);
      final romsSubDir = p.join(dir.path, 'roms');
      FileSystemIndex? romsIndex;
      if (await Directory(romsSubDir).exists()) {
        romsIndex = await FileSystemIndex.build(romsSubDir);
      }

      final Set<String> mappedPathsInThisDir = {};
      final Set<String> matchedRomIdsInThisDir = {};
      final Set<String> allGlobalMappedIds = mappings.values.toSet();

      // PASS 1: File-centric matching (Identify existing files)
      final allLocalEntities = [...index.files.values, ...index.dirs.values];
      if (romsIndex != null) {
        allLocalEntities.addAll([...romsIndex.files.values, ...romsIndex.dirs.values]);
      }

      for (final entityPath in allLocalEntities) {
        if (mappings.containsKey(entityPath)) {
          mappedPathsInThisDir.add(entityPath);
          matchedRomIdsInThisDir.add(mappings[entityPath]!);
          continue;
        }

        final fileName = p.basename(entityPath);
        final fileNameNoExt = p.basenameWithoutExtension(entityPath).toLowerCase();
        
        Game? matchedGame;

        // Strategy A: Exact match against RomM filenames/fsnames
        matchedGame = platformGames.cast<Game?>().firstWhere(
          (g) => g?.fileName == fileName || g?.fsName == fileName,
          orElse: () => null,
        );

        // Strategy B: Clean name match
        if (matchedGame == null) {
          final fNameClean = _cleanName(fileNameNoExt);
          matchedGame = platformGames.cast<Game?>().firstWhere((g) {
            if (g == null) return false;
            if (_cleanName(g.name) == fNameClean) return true;
            final gFileNoExt = p.basenameWithoutExtension(g.fileName ?? '').toLowerCase();
            if (_cleanName(gFileNoExt) == fNameClean) return true;
            final gFsNoExt = p.basenameWithoutExtension(g.fsName ?? '').toLowerCase();
            if (_cleanName(gFsNoExt) == fNameClean) return true;
            return false;
          }, orElse: () => null);
        }

        if (matchedGame != null) {
          debugPrint('[Scanner] File Match: $fileName -> ${matchedGame.name}');
          await _mappingService.updateMapping(entityPath, matchedGame.id);
          mappedPathsInThisDir.add(entityPath);
          matchedRomIdsInThisDir.add(matchedGame.id);
          allGlobalMappedIds.add(matchedGame.id);
          yield RomSyncResult(entityPath, matchedGame.id, game: matchedGame);
        } else {
          // Strategy C: File size match (Very strong indicator if in the correct platform folder)
          final fileSize = index.fileSizes[entityPath] ?? (romsIndex?.fileSizes[entityPath] ?? 0);
          if (fileSize > 1024 * 1024) { // Only for files > 1MB to avoid collisions on small files
            matchedGame = platformGames.cast<Game?>().firstWhere(
              (g) => g?.fileSize == fileSize,
              orElse: () => null,
            );
            if (matchedGame != null) {
              debugPrint('[Scanner] Size Match: $fileName -> ${matchedGame.name} ($fileSize bytes)');
              await _mappingService.updateMapping(entityPath, matchedGame.id);
              mappedPathsInThisDir.add(entityPath);
              matchedRomIdsInThisDir.add(matchedGame.id);
              allGlobalMappedIds.add(matchedGame.id);
              yield RomSyncResult(entityPath, matchedGame.id, game: matchedGame);
            }
          }
        }
      }

      // PASS 2: Game-centric matching (Reverse Mapping)
      // For any game in library NOT yet matched, try to find it on disk using DirectoryService logic
      for (final game in platformGames) {
        if (allGlobalMappedIds.contains(game.id)) continue;

        // Use robust DirectoryService logic with pre-built indices
        String? foundPath = await _directoryService.findExistingRomPath(game, index: index);
        if (foundPath == null && romsIndex != null) {
          foundPath = await _directoryService.findExistingRomPath(game, index: romsIndex);
        }

        if (foundPath != null) {
          debugPrint('[Scanner] REVERSE Match: ${game.name} -> $foundPath');
          await _mappingService.updateMapping(foundPath, game.id);
          mappedPathsInThisDir.add(foundPath);
          matchedRomIdsInThisDir.add(game.id);
          allGlobalMappedIds.add(game.id);
          yield RomSyncResult(foundPath, game.id, game: game);
        }
      }

      // 3. Identify REMOVALS for this platform
      final platformMappings = mappings.entries.where((e) => p.isWithin(dir.path, e.key));
      for (final entry in platformMappings) {
        if (!mappedPathsInThisDir.contains(entry.key) && !await File(entry.key).exists() && !await Directory(entry.key).exists()) {
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
