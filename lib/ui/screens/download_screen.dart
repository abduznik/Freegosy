import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/download_provider.dart';
import '../widgets/download_progress_card.dart';

class DownloadScreen extends ConsumerWidget {
  const DownloadScreen({super.key});

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
                    onCancel: () {
                      ref.read(downloadProvider.notifier).removeDownload(gameId);
                    },
                  );
                },
              ),
      ),
    );
  }
}
