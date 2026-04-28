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
  /// Performs a high-performance sync of the ROM directory.
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

      debugPrint('[RomScanner] Syncing platform: $platformSlug...');
      
      // 1. Fetch ALL games for this platform from RomM
      final List<Game> platformGames = [];
      try {
        int offset = 0;
        const int batchSize = 500;
        while (true) {
          final result = await _rommService.getGamesPage(offset: offset, limit: batchSize, platformId: platformId);
          platformGames.addAll(result.games);
          if (platformGames.length >= result.total || result.games.isEmpty) break;
          offset += batchSize;
        }
      } catch (e) {
        debugPrint('[RomScanner] Error fetching platform games: $e');
        continue;
      }

      // 2. Build local indices for fast lookup
      final index = await FileSystemIndex.build(dir.path);
      final romsSubDir = p.join(dir.path, 'roms');
      FileSystemIndex? romsIndex;
      if (await Directory(romsSubDir).exists()) {
        romsIndex = await FileSystemIndex.build(romsSubDir);
      }

      final Set<String> mappedPathsInThisDir = {};
      final Set<String> matchedRomIdsInThisPlatform = {};
      final Set<String> allGlobalMappedIds = mappings.values.toSet();

      // --- PASS 1: DIRECT LIBRARY-TO-DISK MATCHING (Locked Matches) ---
      // We iterate through the LIBRARY first. This is the most reliable way.
      for (final game in platformGames) {
        // If already mapped globally, check if file still exists
        final existingPath = mappings.entries.where((e) => e.value == game.id).map((e) => e.key).firstOrNull;
        if (existingPath != null) {
          if (await File(existingPath).exists() || await Directory(existingPath).exists()) {
            mappedPathsInThisDir.add(existingPath);
            matchedRomIdsInThisPlatform.add(game.id);
            continue;
          } else {
            await _mappingService.removeMapping(existingPath);
            allGlobalMappedIds.remove(game.id);
          }
        }

        // Try to find the game on disk using official fileName/fsName/Name
        String? foundPath = await _directoryService.findExistingRomPath(game, index: index);
        if (foundPath == null && romsIndex != null) {
          foundPath = await _directoryService.findExistingRomPath(game, index: romsIndex);
        }

        if (foundPath != null) {
          debugPrint('[Scanner] Direct Match: ${game.name} -> $foundPath');
          await _mappingService.updateMapping(foundPath, game.id);
          mappedPathsInThisDir.add(foundPath);
          matchedRomIdsInThisPlatform.add(game.id);
          allGlobalMappedIds.add(game.id);
          yield RomSyncResult(foundPath, game.id, game: game);
        }
      }

      // --- PASS 2: DISK-TO-LIBRARY DISCOVERY (Strict Fallback) ---
      // For any files on disk not yet matched, try to find their corresponding game in the platform library.
      final allLocalEntities = [...index.files.values, ...index.dirs.values];
      if (romsIndex != null) {
        allLocalEntities.addAll([...romsIndex.files.values, ...romsIndex.dirs.values]);
      }

      for (final entityPath in allLocalEntities) {
        if (mappedPathsInThisDir.contains(entityPath)) continue;

        final fileName = p.basename(entityPath);
        final fileNameNoExt = p.basenameWithoutExtension(entityPath).toLowerCase();
        
        // A. Match by exact fileName/fsName
        Game? matchedGame = platformGames.cast<Game?>().firstWhere(
          (g) => (g?.fileName == fileName || g?.fsName == fileName) && !matchedRomIdsInThisPlatform.contains(g!.id),
          orElse: () => null,
        );

        // B. Match by strict clean name + size
        if (matchedGame == null) {
          final fNameClean = _cleanName(fileNameNoExt);
          if (fNameClean.length > 3) {
            final candidates = platformGames.where((g) {
              if (matchedRomIdsInThisPlatform.contains(g.id)) return false;
              if (_cleanName(g.name) == fNameClean) return true;
              final gFileNoExt = p.basenameWithoutExtension(g.fileName ?? '').toLowerCase();
              return _cleanName(gFileNoExt) == fNameClean;
            }).toList();

            if (candidates.length == 1) {
              final candidate = candidates.first;
              final localSize = index.fileSizes[entityPath] ?? (romsIndex?.fileSizes[entityPath] ?? 0);
              // Require size confirmation for fuzzy matches if available
              if (candidate.fileSize > 0 && localSize > 0) {
                final diff = (candidate.fileSize - localSize).abs();
                if (diff < 1024 * 1024 * 5) matchedGame = candidate;
              } else {
                matchedGame = candidate;
              }
            }
          }
        }

        if (matchedGame != null) {
          debugPrint('[Scanner] Discovery Match: $fileName -> ${matchedGame.name}');
          await _mappingService.updateMapping(entityPath, matchedGame.id);
          mappedPathsInThisDir.add(entityPath);
          matchedRomIdsInThisPlatform.add(matchedGame.id);
          allGlobalMappedIds.add(matchedGame.id);
          yield RomSyncResult(entityPath, matchedGame.id, game: matchedGame);
        }
      }

      // 3. Identify REMOVALS
      final platformMappings = mappings.entries.where((e) => p.isWithin(dir.path, e.key));
      for (final entry in platformMappings) {
        if (!mappedPathsInThisDir.contains(entry.key) && !await File(entry.key).exists() && !await Directory(entry.key).exists()) {
          await _mappingService.removeMapping(entry.key);
          yield RomSyncResult(entry.key, entry.value, isRemoved: true);
        }
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
