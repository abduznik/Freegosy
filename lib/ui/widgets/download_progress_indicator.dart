import 'package:flutter/material.dart';
import '../../core/downloader/download_service.dart';

class DownloadProgressIndicator extends StatelessWidget {
  final DownloadProgress progress;
  final bool compact;

  const DownloadProgressIndicator({
    super.key,
    required this.progress,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress.percent > 0 ? progress.percent : null,
          backgroundColor: Colors.grey[800],
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepPurple),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '${progress.status} — ${(progress.percent * 100).toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!compact && progress.totalBytes > 0)
              Text(
                '${(progress.bytesReceived / 1024 / 1024).toStringAsFixed(1)} / '
                '${(progress.totalBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        if (progress.error != null)
          Text(
            'Error: ${progress.error}',
            style: const TextStyle(color: Colors.red, fontSize: 10),
          ),
      ],
    );
  }
}
