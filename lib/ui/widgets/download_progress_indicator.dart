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
        _IndeterminatePulse(
          enabled: progress.percent <= 0 && !progress.isComplete && progress.error == null,
          child: LinearProgressIndicator(
            value: progress.percent > 0 ? progress.percent : null,
            backgroundColor: Colors.grey[800],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepPurple),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                () {
                  String displayStatus = progress.status;
                  // If we are in the download phase and progress is high, show "Almost done"
                  if (progress.status == 'Downloading...' && progress.percent >= 0.8) {
                    displayStatus = 'Almost done...';
                  }
                  
                  return progress.percent > 0 && !progress.isComplete
                    ? '$displayStatus — ${(progress.percent * 100).toStringAsFixed(1)}%'
                    : displayStatus;
                }(),
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

class _IndeterminatePulse extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const _IndeterminatePulse({required this.child, required this.enabled});

  @override
  State<_IndeterminatePulse> createState() => _IndeterminatePulseState();
}

class _IndeterminatePulseState extends State<_IndeterminatePulse> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.enabled) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_IndeterminatePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _controller.repeat(reverse: true);
    } else if (!widget.enabled && oldWidget.enabled) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return FadeTransition(opacity: _animation, child: widget.child);
  }
}
