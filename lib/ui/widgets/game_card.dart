import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/romm/romm_models.dart';

class GameCard extends StatefulWidget {
  final Game game;
  final String? coverUrl;
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
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
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
                    ],
                  ),
                ),
                // Content - fixed height
                ValueListenableBuilder<bool>(
                  valueListenable: _hovering,
                  builder: (context, isHovering, child) {
                    return SizedBox(
                      height: 100, // Slightly increased height for two rows
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
                                child: Column(
                                  children: [
                                    // Top Row: Download/Play and Delete
                                    Row(
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
                                    const SizedBox(height: 4),
                                    // Bottom Row: Push/Pull saves
                                    if (widget.isDownloaded && (widget.onPushSaves != null || widget.onPullSaves != null))
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                        children: [
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
                                        ],
                                      ),
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
