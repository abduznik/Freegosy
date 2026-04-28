import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/romm/romm_models.dart';
import 'download_provider.dart';
import 'romm_provider.dart';
import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';

final isScanningProvider = StateProvider<bool>((ref) => false);

class DownloadedGamesCache extends StateNotifier<Map<String, bool>> {
  final Ref _ref;
  bool _isSyncing = false;
  Timer? _syncTimer;
  Timer? _periodicTimer;
  
  DownloadedGamesCache(this._ref) : super({}) {
    _init();
  }

  bool get isSyncing => _isSyncing;

  void _init() {
    // Listen for mapping service to be ready, then refresh
    _ref.listen(romMappingServiceProvider, (prev, next) {
      if (next.hasValue) {
        refresh();
      }
    }, fireImmediately: true);
    
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

    // Start incremental sync in background after a short delay
    _syncTimer = Timer(const Duration(seconds: 3), () => startIncrementalSync());

    // Periodical refresh every 5 minutes
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (_) => startIncrementalSync());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _periodicTimer?.cancel();
    _isSyncing = false;
    super.dispose();
  }

  /// Quickly populates the cache from locally stored mappings.
  /// Also verifies they actually exist on disk to prevent 'zombie' games.
  Future<void> refresh() async {
    final mappingServiceAsync = _ref.read(romMappingServiceProvider);
    final metadataCacheAsync = _ref.read(metadataCacheServiceProvider);
    final rommService = _ref.read(rommServiceProvider);
    
    if (!mappingServiceAsync.hasValue || !metadataCacheAsync.hasValue) return;
    
    final mappingService = mappingServiceAsync.value!;
    final metadataCache = metadataCacheAsync.value!;
    final mappings = mappingService.getMappings();
    final Map<String, bool> newState = {};
    
    final Set<String> missingMetadataIds = {};
    final cachedIds = metadataCache.cachedGames.map((g) => g.id).toSet();

    for (final entry in mappings.entries) {
      final path = entry.key;
      final romId = entry.value;
      
      // DISK CHECK: If the file was deleted manually, clean up the mapping
      if (await io.File(path).exists() || await io.Directory(path).exists()) {
        newState[romId] = true;
        if (!cachedIds.contains(romId)) {
          missingMetadataIds.add(romId);
        }
      } else {
        debugPrint('[DownloadedGamesCache] Zombie detected: $path no longer exists. Removing.');
        await mappingService.removeMapping(path);
      }
    }
    
    state = newState;
    debugPrint('[DownloadedGamesCache] Loaded ${state.length} active mappings (${missingMetadataIds.length} missing metadata).');

    // AUTO-REPAIR: Fetch missing metadata in small batches
    if (missingMetadataIds.isNotEmpty && rommService != null) {
      debugPrint('[DownloadedGamesCache] Repairing metadata for ${missingMetadataIds.length} games...');
      final List<Game> repairedGames = [];
      for (final id in missingMetadataIds.take(20)) { // Limit to 20 per refresh to avoid spam
        final game = await rommService.getGame(id);
        if (game != null) repairedGames.add(game);
      }
      if (repairedGames.isNotEmpty) {
        await metadataCache.saveGames(repairedGames);
        debugPrint('[DownloadedGamesCache] Repaired ${repairedGames.length} metadata entries.');
        // Don't call refresh again to avoid loops, the next state update will pick it up
      }
    }
  }

  /// Runs the high-performance incremental sync.
  Future<void> startIncrementalSync({bool force = false}) async {
    if (_isSyncing) return;
    
    final scanner = _ref.read(romScannerServiceProvider);
    final dirService = _ref.read(directoryServiceProvider).asData?.value;
    final metadataCache = _ref.read(metadataCacheServiceProvider).asData?.value;
    
    if (scanner == null || dirService == null || metadataCache == null) {
      // Retry in a bit if services aren't ready
      Future.delayed(const Duration(seconds: 10), () => startIncrementalSync());
      return;
    }

    _isSyncing = true;
    _ref.read(isScanningProvider.notifier).state = true;
    debugPrint('[DownloadedGamesCache] Starting incremental sync...');

    try {
      // 1. Global Pruning Phase
      final prunedCount = await scanner.pruneDeadMappings();
      if (prunedCount > 0) {
        debugPrint('[DownloadedGamesCache] Pruned $prunedCount dead mappings.');
      }

      final romsRoot = await dirService.getRomsDirectory();
      final List<Game> matchedMetadataBuffer = [];
      final Map<String, bool> sessionMatches = {};
      
      int count = 0;
      await for (final result in scanner.sync(romsRoot, force: force)) {
        // Handle removals IMMEDIATELY
        if (result.isRemoved && result.romId != null) {
          final newState = Map<String, bool>.from(state);
          newState.remove(result.romId);
          state = newState;
          continue;
        }

        if (result.romId != null) {
          sessionMatches[result.romId!] = true;
          if (result.game != null) {
            matchedMetadataBuffer.add(result.game!);
          }

          count++;
          // Update UI and Metadata Cache every 20 games for performance + persistence
          if (count % 20 == 0) {
            state = {...state, ...sessionMatches};
            if (matchedMetadataBuffer.isNotEmpty) {
              await metadataCache.saveGames(matchedMetadataBuffer);
              matchedMetadataBuffer.clear();
            }
          } else if (count % 5 == 0) {
            // Just update UI every 5 for the 'pop-in' effect
            state = {...state, ...sessionMatches};
          }
        }
      }

      // Final state and metadata update
      state = {...state, ...sessionMatches};
      if (matchedMetadataBuffer.isNotEmpty) {
        debugPrint('[DownloadedGamesCache] Final batch persisting ${matchedMetadataBuffer.length} games...');
        await metadataCache.saveGames(matchedMetadataBuffer);
      }
    } catch (e) {
      debugPrint('[DownloadedGamesCache] Sync error: $e');
    } finally {
      _isSyncing = false;
      _ref.read(isScanningProvider.notifier).state = false;
      debugPrint('[DownloadedGamesCache] Incremental sync complete.');
      // Final refresh to ensure everything is flushed and matched up
      await refresh();
    }
  }

  bool isDownloaded(String gameId) => state[gameId] ?? false;
}

final downloadedGamesCacheProvider = StateNotifierProvider<DownloadedGamesCache, Map<String, bool>>((ref) {
  return DownloadedGamesCache(ref);
});
