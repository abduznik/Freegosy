import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        continue;
      }

      // Migration: clear Windows game mappings that point to individual files
      // instead of folders. Before the folder-based lookup fix, the ROM scanner
      // picked random large files (.xnb, .dll) as the "ROM" for Windows games.
      // Now Windows games should map to their game folder, not a file inside.
      if (_isWindowsGameMapping(path)) {
        debugPrint('[Sanity] Clearing stale Windows game mapping (file instead of folder): $path');
        await _mappingService.removeMapping(path);
        removedCount++;
      }
    }

    if (removedCount > 0) {
      debugPrint('[Sanity] Pruned $removedCount stale entries.');
    }
  }

  /// Returns true if [path] looks like a Windows game ROM mapping that points
  /// to an individual file inside a game folder (not the folder itself).
  /// Windows games are folder-based — the ROM path should be a directory.
  static bool _isWindowsGameMapping(String path) {
    final lower = path.toLowerCase();
    // Check if the path is inside a Windows ROM directory
    final isWinPath = lower.contains('\\win\\') || lower.contains('/win/') ||
        lower.contains('\\windows\\') || lower.contains('/windows/') ||
        lower.contains('\\pc\\') || lower.contains('/pc/');
    if (!isWinPath) return false;
    // If it's a file (not a directory), it's a stale mapping
    return io.File(path).existsSync() && !io.Directory(path).existsSync();
  }
}

final fileSanityServiceProvider = Provider<FileSanityService?>((ref) {
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
