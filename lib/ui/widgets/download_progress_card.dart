import 'package:flutter/material.dart';
import '../../core/downloader/download_service.dart';
import 'download_progress_indicator.dart';
import 'focus_effect_wrapper.dart';

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

  Widget _buildIconButton(BuildContext context, {required IconData icon, required VoidCallback? onTap, Color? color}) {
    final theme = Theme.of(context);
    return FocusEffectWrapper(
      onTap: onTap,
      borderRadius: 12.0,
      scaleFactor: 1.1,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, size: 20, color: color ?? theme.colorScheme.onSurface),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isPaused = progress.isPaused;
    final bool isComplete = progress.isComplete;
    final bool hasError = progress.error != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Text(
            gameName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: DownloadProgressIndicator(progress: progress),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isComplete && !hasError && onPause != null && onResume != null) ...[
                _buildIconButton(
                  context,
                  icon: isPaused ? Icons.play_arrow : Icons.pause,
                  onTap: isPaused ? onResume : onPause,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
              ],
              _buildIconButton(
                context,
                icon: isComplete ? Icons.check : Icons.close,
                onTap: onCancel,
                color: isComplete ? Colors.green : theme.colorScheme.error,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
