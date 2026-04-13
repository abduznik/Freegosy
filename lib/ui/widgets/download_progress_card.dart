import 'package:flutter/material.dart';
import '../../core/downloader/download_service.dart';
import 'download_progress_indicator.dart';

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
      title: Text(gameName, overflow: TextOverflow.ellipsis),
      subtitle: DownloadProgressIndicator(progress: progress),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        onPressed: onCancel,
        tooltip: 'Cancel',
      ),
    );
  }
}
