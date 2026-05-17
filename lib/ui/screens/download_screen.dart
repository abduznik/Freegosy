import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/download_provider.dart';
import '../widgets/download_progress_card.dart';
import '../widgets/focus_effect_wrapper.dart';

class DownloadScreen extends ConsumerWidget {
  const DownloadScreen({super.key});

  Future<bool> _showCancelConfirmation(BuildContext context, String gameName) async {
    final theme = Theme.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Cancel Download'),
        content: Text('Are you sure you want to cancel downloading $gameName? This will delete the partial file.'),
        actions: [
          FocusEffectWrapper(
            onTap: () => Navigator.pop(context, false),
            borderRadius: 16.0,
            useSafeScale: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Keep',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FocusEffectWrapper(
            onTap: () => Navigator.pop(context, true),
            borderRadius: 16.0,
            useSafeScale: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.2),
                border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Cancel Download',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'freegosy_logo.png',
              height: 32,
              width: 32,
            ),
            const SizedBox(width: 12),
            const Text('Downloads'),
          ],
        ),
      ),
      body: ExcludeSemantics(
        child: downloads.isEmpty
            ? const Center(child: Text('No active downloads'))
            : ListView.builder(
                itemCount: downloads.length,
                itemBuilder: (context, index) {
                  final gameId = downloads.keys.elementAt(index);
                  final progress = downloads[gameId]!;
                  return DownloadProgressCard(
                    gameName: progress.gameName,
                    progress: progress,
                    onPause: () {
                      ref.read(downloadProvider.notifier).pauseDownload(gameId);
                    },
                    onResume: () {
                      if (progress.game != null && progress.downloadUrl != null) {
                        ref.read(downloadProvider.notifier).startDownload(
                              progress.game!,
                              progress.downloadUrl!,
                            );
                      }
                    },
                    onCancel: () async {
                      if (progress.isComplete || progress.error != null) {
                        ref.read(downloadProvider.notifier).cancelDownload(gameId);
                      } else if (await _showCancelConfirmation(context, progress.gameName)) {
                        ref.read(downloadProvider.notifier).cancelDownload(gameId);
                      }
                    },
                  );
                },
              ),
      ),
    );
  }
}
