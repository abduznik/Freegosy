import 'package:flutter/material.dart';
import '../../core/downloader/download_service.dart';

class DownloadProgressCard extends StatelessWidget {
  final String gameName;
  final DownloadProgress progress;
  final VoidCallback onCancel;

  const DownloadProgressCard({
    super.key,
    required this.gameName,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(gameName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.percent),
          const SizedBox(height: 4),
          Text(
            '${progress.status} — ${(progress.percent * 100).toStringAsFixed(1)}% - '
            '${(progress.bytesReceived / 1024 / 1024).toStringAsFixed(1)} MB / '
            '${(progress.totalBytes / 1024 / 1024).toStringAsFixed(1)} MB',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (progress.error != null)
            Text(
              'Error: ${progress.error}',
              style: const TextStyle(color: Colors.red),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        onPressed: onCancel,
        tooltip: 'Cancel',
      ),
    );
  }
}
