import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/romm/romm_models.dart';
import '../../providers/library_provider.dart';

class GameCard extends ConsumerStatefulWidget {
  final Game game;
  final String? coverUrl;
  final String? platformLogoUrl;
  final VoidCallback onDownload;
  final VoidCallback onLaunch;
  final VoidCallback onDelete;
  final VoidCallback? onPushSaves;
  final VoidCallback? onPullSaves;
  final bool isDownloaded;
  final bool showTitle;
  final bool showButtonsOnHover;

  const GameCard({
    super.key,
    required this.game,
    this.coverUrl,
    this.platformLogoUrl,
    required this.onDownload,
    required this.onLaunch,
    required this.onDelete,
    this.onPushSaves,
    this.onPullSaves,
    this.isDownloaded = false,
    this.showTitle = true,
    this.showButtonsOnHover = false,
  });

  @override
  ConsumerState<GameCard> createState() => _GameCardState();
}

class _GameCardState extends ConsumerState<GameCard> {
  final ValueNotifier<bool> _hovering = ValueNotifier(false);

  @override
  void dispose() {
    _hovering.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onLongPress: () => _showContextMenu(context),
        child: MouseRegion(
          onEnter: (_) => _hovering.value = true,
          onExit: (_) => _hovering.value = false,
          child: Card(
            elevation: 2,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cover image - fills remaining space
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      (widget.coverUrl == null || widget.coverUrl!.isEmpty)
                          ? const Center(child: Icon(Icons.sports_esports, size: 48))
                          : CachedNetworkImage(
                              imageUrl: widget.coverUrl!,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              memCacheWidth: 300,
                              memCacheHeight: 400,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[300],
                                child: const Center(
                                  child: Icon(Icons.image, color: Colors.grey),
                                ),
                              ),
                              errorWidget: (context, url, error) => const Center(
                                child: Icon(Icons.sports_esports, size: 48),
                              ),
                            ),
                      if (widget.isDownloaded)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, size: 14, color: Colors.white),
                          ),
                        ),
                      if (widget.platformLogoUrl != null && widget.platformLogoUrl!.isNotEmpty)
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Consumer(
                                builder: (context, ref, _) {
                                  final logoAsync = widget.platformLogoUrl != null && widget.platformLogoUrl!.isNotEmpty
                                      ? ref.watch(platformLogoCacheProvider(widget.platformLogoUrl!))
                                      : const AsyncValue<Uint8List?>.data(null);
                                  return logoAsync.when(
                                    data: (bytes) {
                                      if (bytes == null) return const SizedBox.shrink();
                                      return Opacity(
                                        opacity: 0.9,
                                        child: FractionallySizedBox(
                                          widthFactor: 0.3,
                                          heightFactor: 0.3,
                                          child: SvgPicture.memory(
                                            bytes,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      );
                                    },
                                    loading: () => const SizedBox.shrink(),
                                    error: (_, _) => const SizedBox.shrink(),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Content - fixed height
                ValueListenableBuilder<bool>(
                  valueListenable: _hovering,
                  builder: (context, isHovering, child) {
                    return SizedBox(
                      height: 80,
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!widget.showButtonsOnHover || !isHovering)
                              if (widget.showTitle)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                                  child: Text(
                                    widget.game.displayName,
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                )
                              else
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4.0),
                                  child: Center(
                                    child: Icon(Icons.more_horiz, size: 16, color: Colors.grey),
                                  ),
                                ),
                            
                            if (!widget.showButtonsOnHover || isHovering)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    if (!widget.isDownloaded)
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 22,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.download),
                                        onPressed: widget.onDownload,
                                        tooltip: 'Download',
                                      )
                                    else ...[
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 22,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.play_arrow),
                                        onPressed: widget.onLaunch,
                                        tooltip: 'Play',
                                      ),
                                      if (widget.onPushSaves != null)
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          iconSize: 20,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(Icons.cloud_upload),
                                          onPressed: widget.onPushSaves,
                                          tooltip: 'Push saves',
                                        ),
                                      if (widget.onPullSaves != null)
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          iconSize: 20,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(Icons.cloud_download),
                                          onPressed: widget.onPullSaves,
                                          tooltip: 'Pull saves',
                                        ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 20,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                                        onPressed: () => _confirmDelete(context),
                                        tooltip: 'Delete ROM',
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete ROM'),
          content: const Text('Are you sure you want to delete the local files for this game?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                widget.onDelete();
              },
            ),
          ],
        );
      },
    );
  }

  void _showContextMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Context Menu'),
          content: const Text('Context menu functionality will be implemented here.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
