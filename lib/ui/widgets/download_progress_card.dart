import 'package:flutter/material.dart';
import '../../core/downloader/download_service.dart';
import 'download_progress_indicator.dart';

class DownloadProgressCard extends StatelessWidget {
  final String gameName;
  final DownloadProgress progress;
  final VoidCallback onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  const DownloadProgressCard({
    super.key,
    required this.gameName,
    required this.progress,
    required this.onCancel,
    this.onPause,
    this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPaused = progress.isPaused;
    final bool isComplete = progress.isComplete;
    final bool hasError = progress.error != null;

    return ListTile(
      title: Text(gameName, overflow: TextOverflow.ellipsis),
      subtitle: DownloadProgressIndicator(progress: progress),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isComplete && !hasError && onPause != null && onResume != null)
            IconButton(
              icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
              onPressed: isPaused ? onResume : onPause,
              tooltip: isPaused ? 'Resume' : 'Pause',
            ),
          IconButton(
            icon: Icon(isComplete ? Icons.check : Icons.close),
            onPressed: onCancel,
            tooltip: isComplete ? 'Clear' : 'Cancel',
          ),
        ],
      ),
    );
  }
}
