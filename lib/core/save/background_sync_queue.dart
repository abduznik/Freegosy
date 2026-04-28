import 'dart:io' as io;
import 'package:flutter/material.dart';
import '../romm/romm_service.dart';
import 'backup_repository.dart';

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
    if (_isRunning) return;

    final pending = backupRepo.getUnsyncedEntries();
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

        final uploadFilename = 'freegosy_${item.romId}_${item.entry.timestamp.millisecondsSinceEpoch}_${item.entry.md5Hash}.zip';

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
