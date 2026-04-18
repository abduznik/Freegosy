import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/romm/romm_models.dart';
import 'download_provider.dart';
import 'romm_provider.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

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
  Future<void> refresh() async {
    final mappingServiceAsync = _ref.read(romMappingServiceProvider);
    if (!mappingServiceAsync.hasValue) return;
    
    final mappingService = mappingServiceAsync.value!;
    final mappings = mappingService.getMappings();
    final Map<String, bool> newState = {};
    for (final romId in mappings.values) {
      newState[romId] = true;
    }
    state = newState;
    debugPrint('[DownloadedGamesCache] Loaded ${state.length} cached mappings.');
  }

  /// Runs the high-performance incremental sync.
  Future<void> startIncrementalSync() async {
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
    debugPrint('[DownloadedGamesCache] Starting incremental sync...');

    try {
      final romsRoot = await dirService.getRomsDirectory();
      final List<Game> matchedMetadataBuffer = [];
      final Map<String, bool> sessionMatches = {};
      
      int count = 0;
      await for (final result in scanner.sync(romsRoot)) {
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
