import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/romm/romm_models.dart';
import 'download_provider.dart';
import 'romm_provider.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class DownloadedGamesCache extends StateNotifier<Map<String, bool>> {
  final Ref _ref;
  bool _isDeepScanning = false;
  
  DownloadedGamesCache(this._ref) : super({}) {
    _init();
  }

  bool get isDeepScanning => _isDeepScanning;

  void _init() {
    // Initial scan of whatever is already in memory
    refresh();
    
    // Listen to download progress
    _ref.listen(downloadProvider, (prev, next) {
      bool changed = false;
      final newState = Map<String, bool>.from(state);
      
      for (final entry in next.entries) {
        if (entry.value.isComplete && newState[entry.key] != true) {
          newState[entry.key] = true;
          changed = true;
        }
      }
      
      if (changed) {
        state = newState;
      }
    });

    // Start deep scan in background after a short delay
    Future.delayed(const Duration(seconds: 5), () => startDeepScan());

    // Periodical refresh every 2 minutes to catch external filesystem changes
    Timer.periodic(const Duration(minutes: 2), (_) => refresh());
  }

  /// Quickly refreshes the download status for games currently in the metadata cache.
  Future<void> refresh() async {
    final directoryService = _ref.read(directoryServiceProvider).asData?.value;
    if (directoryService == null) return;

    final downloadedByPlatform = await directoryService.getAllDownloadedFileNamesByPlatform();
    final metadataCache = _ref.read(metadataCacheServiceProvider).asData?.value;
    
    final List<Game> gamesToScan = metadataCache?.cachedGames ?? [];
    if (gamesToScan.isEmpty) return;

    final Map<String, bool> newState = Map<String, bool>.from(state);
    for (final game in gamesToScan) {
      final platformSlug = game.platformSlug ?? '';
      final downloadedNames = downloadedByPlatform[platformSlug] ?? {};
      
      final fileName = (game.fsName ?? game.fileName ?? game.name)
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .toLowerCase();
      
      newState[game.id] = downloadedNames.contains(fileName);
    }
    state = newState;
  }

  /// Aggressively fetches all games from RomM in the background to find EVERYTHING downloaded.
  Future<void> startDeepScan() async {
    if (_isDeepScanning) return;
    
    final service = _ref.read(rommServiceProvider);
    final dirService = _ref.read(directoryServiceProvider).asData?.value;
    final metadataCache = _ref.read(metadataCacheServiceProvider).asData?.value;
    
    if (service == null || dirService == null || metadataCache == null) {
      // Retry in a bit if services aren't ready
      Future.delayed(const Duration(seconds: 10), () => startDeepScan());
      return;
    }

    _isDeepScanning = true;
    debugPrint('[DownloadedGamesCache] Starting background deep scan...');

    try {
      final platforms = await service.getPlatforms();
      final downloadedByPlatform = await dirService.getAllDownloadedFileNamesByPlatform();
      
      if (downloadedByPlatform.isEmpty) {
        _isDeepScanning = false;
        return;
      }

      final Map<String, bool> newState = Map<String, bool>.from(state);
      
      for (final platform in platforms) {
        final slug = platform.slug;
        if (!downloadedByPlatform.containsKey(slug) && !downloadedByPlatform.containsKey(platform.name.toLowerCase())) {
          continue;
        }

        final localFiles = downloadedByPlatform[slug] ?? downloadedByPlatform[platform.name.toLowerCase()] ?? {};
        if (localFiles.isEmpty) continue;

        debugPrint('[DownloadedGamesCache] Scanning platform ${platform.name} for ${localFiles.length} local files...');

        int offset = 0;
        const int limit = 100;
        
        while (true) {
          final result = await service.getGamesPage(
            platformId: platform.id.toString(),
            offset: offset,
            limit: limit,
          );

          if (result.games.isEmpty) break;

          // Save to metadata cache so they are available offline
          await metadataCache.saveGames(result.games);

          for (final game in result.games) {
            final fileName = (game.fsName ?? game.fileName ?? game.name)
                .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
                .toLowerCase();
            
            if (localFiles.contains(fileName)) {
              newState[game.id] = true;
            } else {
              // Also check without extension if local file might have different extension
              final stem = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
              bool found = false;
              for (final localFile in localFiles) {
                if (localFile.startsWith(stem)) {
                  found = true;
                  break;
                }
              }
              if (found) newState[game.id] = true;
            }
          }

          // Update state incrementally so UI sees progress
          state = Map<String, bool>.from(newState);

          offset += limit;
          if (offset >= result.total) break;
          
          // Small gap to not overwhelm the server
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      debugPrint('[DownloadedGamesCache] Deep scan error: $e');
    } finally {
      _isDeepScanning = false;
      debugPrint('[DownloadedGamesCache] Background deep scan complete.');
    }
  }

  bool isDownloaded(String gameId) => state[gameId] ?? false;
}

final downloadedGamesCacheProvider = StateNotifierProvider<DownloadedGamesCache, Map<String, bool>>((ref) {
  return DownloadedGamesCache(ref);
});
