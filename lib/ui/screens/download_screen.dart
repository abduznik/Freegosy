import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/download_provider.dart';
import '../widgets/download_progress_card.dart';

class DownloadScreen extends ConsumerWidget {
  const DownloadScreen({super.key});

  Future<bool> _showCancelConfirmation(BuildContext context, String gameName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Download'),
        content: Text('Are you sure you want to cancel downloading $gameName? This will delete the partial file.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Download', style: TextStyle(color: Colors.red)),
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
                      if (await _showCancelConfirmation(context, progress.gameName)) {
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
