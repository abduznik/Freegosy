import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/romm/romm_models.dart';

class GameCard extends StatefulWidget {
  final Game game;
  final String? coverUrl;
  final VoidCallback onDownload;
  final VoidCallback onLaunch;
  final VoidCallback? onSyncSaves;
  final bool isDownloaded;
  final bool showTitle;
  final bool showButtonsOnHover;

  const GameCard({
    super.key,
    required this.game,
    this.coverUrl,
    required this.onDownload,
    required this.onLaunch,
    this.onSyncSaves,
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
                      height: 90,
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!widget.showButtonsOnHover || !isHovering)
                              if (widget.showTitle)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
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
                                  padding: EdgeInsets.symmetric(vertical: 1.0),
                                  child: Center(
                                    child: Icon(Icons.more_horiz, size: 16, color: Colors.grey),
                                  ),
                                ),
                            
                            if (!widget.showButtonsOnHover || isHovering)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      iconSize: 22,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.download),
                                      onPressed: widget.onDownload,
                                      tooltip: 'Download',
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      iconSize: 22,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.play_arrow),
                                      onPressed: widget.onLaunch,
                                      tooltip: 'Launch',
                                    ),
                                    if (widget.onSyncSaves != null)
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 18,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.cloud_upload),
                                        onPressed: widget.onSyncSaves,
                                        tooltip: 'Sync saves',
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
