import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:developer' as dev;
import '../../core/romm/romm_models.dart';
import '../../core/save/backup_entry.dart';
import '../../core/error/error_handler.dart';
import '../../providers/romm_provider.dart';


// ---------------------------------------------------------------------------
// BackupHistorySheet
// ---------------------------------------------------------------------------

/// Bottom sheet that lists local save backups for [game] and allows restoring
/// any of them. Displayed from [GameDetailScreen] via [show].
class BackupHistorySheet extends ConsumerWidget {
  final Game game;
  final String romPath;

  const BackupHistorySheet({
    super.key,
    required this.game,
    required this.romPath,
  });

  // Public entry-point ---------------------------------------------------------

  static Future<void> show(
    BuildContext context, {
    required Game game,
    required String romPath,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BackupHistorySheet(game: game, romPath: romPath),
    );
  }

  // Build ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(backupRepositoryProvider);
    final entries = repo.getEntries(game.id);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1a1a1a),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Colors.white70, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Local Backups',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${entries.length} / 8 slots used',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white12),

            // List
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.save_outlined, color: Colors.white24, size: 48),
                            SizedBox(height: 16),
                            Text(
                              'No local backups yet.\nLaunch the game to create a restore point automatically.',
                              style: TextStyle(color: Colors.white38, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: entries.length,
                      itemBuilder: (context, index) => _BackupTile(
                        index: index,
                        entry: entries[index],
                        game: game,
                        romPath: romPath,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _BackupTile
// ---------------------------------------------------------------------------

class _BackupTile extends ConsumerWidget {
  final int index;
  final BackupEntry entry;
  final Game game;
  final String romPath;

  const _BackupTile({
    required this.index,
    required this.entry,
    required this.game,
    required this.romPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts = entry.timestamp.toLocal();
    final dateStr =
        '${ts.day.toString().padLeft(2, '0')} ${_monthName(ts.month)} ${ts.year}'
        ' · ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    final label = index == 0 ? 'Latest' : '#${index + 1}';
    final isLatest = index == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(12),
        border: isLatest
            ? Border.all(color: Colors.blueAccent.withValues(alpha: 0.4), width: 1)
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isLatest ? Colors.blueAccent.withValues(alpha: 0.15) : Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isLatest ? Colors.blueAccent : Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Text(
          dateStr,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'MD5: ${entry.md5Hash.length >= 8 ? entry.md5Hash.substring(0, 8) : entry.md5Hash}…',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(width: 8),
            Icon(
              entry.isSynced ? Icons.cloud_done : Icons.cloud_upload_outlined,
              size: 14,
              color: entry.isSynced ? Colors.green.withValues(alpha: 0.7) : Colors.orange.withValues(alpha: 0.7),
            ),
          ],
        ),
        trailing: _RestoreButton(entry: entry, game: game, romPath: romPath),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RestoreButton
// ---------------------------------------------------------------------------

class _RestoreButton extends ConsumerStatefulWidget {
  final BackupEntry entry;
  final Game game;
  final String romPath;

  const _RestoreButton({
    required this.entry,
    required this.game,
    required this.romPath,
  });

  @override
  ConsumerState<_RestoreButton> createState() => _RestoreButtonState();
}

class _RestoreButtonState extends ConsumerState<_RestoreButton> {
  bool _loading = false;

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: const Text('Restore Backup', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will overwrite your current save with the selected backup. '
          'A safety snapshot of your current save will be created first.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);

    try {
      final backupService = ref.read(backupServiceProvider);
      final syncServiceAsync = ref.read(saveSyncServiceProvider);
      final syncService = syncServiceAsync.asData?.value;

      if (syncService == null) {
        ErrorHandler.showInfo(context, 'Sync Unavailable', message: 'Save sync service not ready.');
        return;
      }

      // 1. Safety snapshot of the current state before overwriting
      final safetyBackup = await backupService.createImmediate(widget.game, widget.romPath, syncService);
      if (safetyBackup != null) {
        final backupRepo = ref.read(backupRepositoryProvider);
        await backupRepo.addEntry(
          widget.game.id,
          BackupEntry(
            timestamp: DateTime.now(),
            md5Hash: safetyBackup.md5,
            localZipPath: safetyBackup.zipPath,
          ),
        );
      }

      // 2. Restore selected backup
      final ok = await backupService.restore(
        widget.entry.localZipPath,
        widget.game,
        widget.romPath,
        syncService,
      );

      if (!mounted) return;
      if (ok) {
        ErrorHandler.showSuccess(context, 'Restored', message: 'Save restored successfully.');
        if (Navigator.canPop(context)) Navigator.pop(context);
      } else {
        ErrorHandler.showException(context, Exception('Restore failed — file may be missing.'),
            contextLabel: 'Restore Backup');
      }
    } catch (e, st) {
      dev.log('Restore from backup sheet failed', error: e, stackTrace: st);
      if (mounted) ErrorHandler.showException(context, e, contextLabel: 'Restore Backup');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: ElevatedButton(
        onPressed: _loading ? null : _restore,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent.withValues(alpha: 0.85),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: _loading
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Restore', style: TextStyle(fontSize: 12, color: Colors.white)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _monthName(int month) {
  const names = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return names[month.clamp(1, 12)];
}
