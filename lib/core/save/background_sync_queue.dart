import 'dart:io' as io;
import 'package:flutter/material.dart';
import '../romm/romm_service.dart';
import 'backup_repository.dart';
import 'backup_entry.dart';

import '../../main.dart' show scaffoldMessengerKey;

/// Processes pending local backups serially to avoid network and CPU spikes.
class BackgroundSyncQueue {
  static bool _isRunning = false;

  /// Starts processing the queue serially. Safe to call multiple times; 
  /// it will simply return if already running.
  static Future<void> processQueue(
    RommService rommService,
    BackupRepository backupRepo, [
    ScaffoldMessengerState? customMessenger,
  ]) async {
    debugPrint('[BackgroundSyncQueue] processQueue triggered.');
    if (_isRunning) {
      debugPrint('[BackgroundSyncQueue] Queue is already running. Bailing.');
      return;
    }

    final rawPending = backupRepo.getUnsyncedEntries();
    
    // Group by romId and only keep the newest entry for each game to be efficient
    final Map<String, ({String romId, BackupEntry entry})> newestPerGame = {};
    for (final item in rawPending) {
      final existing = newestPerGame[item.romId];
      if (existing == null || item.entry.timestamp.isAfter(existing.entry.timestamp)) {
        newestPerGame[item.romId] = item;
      }
    }

    final pending = newestPerGame.values.toList();
    // Sort oldest game first to maintain chronological order across different games
    pending.sort((a, b) => a.entry.timestamp.compareTo(b.entry.timestamp));

    // Mark skipped entries as synced so they don't stay in the queue
    for (final item in rawPending) {
      if (!pending.contains(item)) {
        await backupRepo.markAsSynced(item.romId, item.entry);
      }
    }

    debugPrint('[BackgroundSyncQueue] Sweep complete. Found ${rawPending.length} pending, consolidated to ${pending.length} unique game uploads.');
    if (pending.isEmpty) return;

    _isRunning = true;
    int syncedCount = 0;
    
    final messenger = customMessenger ?? scaffoldMessengerKey.currentState;

    try {
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1565C0),
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Syncing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('Syncing ${pending.length} offline saves to cloud...', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      for (final item in pending) {
        // 1. Check connectivity before attempting upload
        if (rommService.isOffline.value) {
          debugPrint('[BackgroundSyncQueue] Connection lost. Stopping queue.');
          break;
        }

        // We can do a quick socket check to be absolutely sure before large file ops
        try {
          final uri = Uri.parse(rommService.config.baseUrl);
          final socket = await io.Socket.connect(
            uri.host,
            uri.port == 0 ? (uri.scheme == 'https' ? 443 : 80) : uri.port,
            timeout: const Duration(seconds: 3),
          );
          await socket.close();
        } catch (e) {
          debugPrint('[BackgroundSyncQueue] Connectivity check failed. Stopping queue.');
          break;
        }

        final zipFile = io.File(item.entry.localZipPath);
        if (!await zipFile.exists()) {
          // If the physical file was deleted, mark it as synced to clear it from queue
          await backupRepo.markAsSynced(item.romId, item.entry);
          continue;
        }

        debugPrint('[BackgroundSyncQueue] Pushing ${zipFile.path} to RomM...');

        final game = await rommService.getGame(item.romId);
        final displayStem = game?.displayName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_') ?? 'freegosy_${item.romId}';
        final uploadFilename = '$displayStem.zip';

        final success = await rommService.uploadSave(
          item.romId,
          zipFile,
          overrideFilename: uploadFilename,
        );

        if (success) {
          await backupRepo.markAsSynced(item.romId, item.entry);
          syncedCount++;
          debugPrint('[BackgroundSyncQueue] Upload successful. Throttling for 5 seconds...');
          // Throttle
          await Future.delayed(const Duration(seconds: 5));
        } else {
          debugPrint('[BackgroundSyncQueue] Upload failed. Stopping queue.');
          break;
        }
      }

      if (syncedCount > 0) {
        messenger?.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 3),
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cloud Sync', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('Cloud sync complete. $syncedCount saves uploaded.', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } finally {
      _isRunning = false;
    }
  }
}
