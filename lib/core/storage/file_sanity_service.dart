import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/rom_mapping_service.dart';
import 'package:freegosy/core/storage/download_cache_service.dart';
import 'package:freegosy/providers/romm_provider.dart';

class FileSanityService {
  final RomMappingService _mappingService;
  final DownloadCacheService _cacheService;
  Timer? _timer;

  FileSanityService(this._mappingService, this._cacheService);

  void start() {
    _timer?.cancel();
    // Run every 10 minutes
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => pruneStaleEntries());
    // Also run once immediately
    pruneStaleEntries();
  }

  void stop() {
    _timer?.cancel();
  }

  Future<void> pruneStaleEntries() async {
    debugPrint('[Sanity] Checking for stale ROM mappings...');
    final mappings = _mappingService.getMappings();
    int removedCount = 0;

    for (final entry in mappings.entries) {
      final path = entry.key;
      final file = io.File(path);
      
      if (!file.existsSync()) {
        debugPrint('[Sanity] File no longer exists, removing mapping: $path');
        await _mappingService.removeMapping(path);
        _cacheService.removeFile(io.File(path).path); // Best effort removal from cache
        removedCount++;
      }
    }

    if (removedCount > 0) {
      debugPrint('[Sanity] Pruned $removedCount stale entries.');
    }
  }
}

final fileSanityServiceProvider = Provider<FileSanityService?>((ref) {
  final dirService = ref.watch(directoryServiceProvider).asData?.value;
  final mappingServiceAsync = ref.watch(romMappingServiceProvider);
  final cacheService = ref.watch(downloadCacheServiceProvider);

  if (!mappingServiceAsync.hasValue) {
     return null;
  }

  final service = FileSanityService(mappingServiceAsync.value!, cacheService);
  service.start();
  
  ref.onDispose(() => service.stop());
  return service;
});
