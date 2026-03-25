import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/romm/romm_models.dart';
import '../../providers/romm_provider.dart';

class GameCard extends ConsumerStatefulWidget {
  final Game game;
  final VoidCallback onDownload;
  final VoidCallback onLaunch;
  final VoidCallback? onSyncSaves;
  final bool isDownloaded;
  final bool showTitle;
  final bool showButtonsOnHover;

  const GameCard({
    super.key,
    required this.game,
    required this.onDownload,
    required this.onLaunch,
    this.onSyncSaves,
    this.isDownloaded = false,
    this.showTitle = true,
    this.showButtonsOnHover = false,
  });

  @override
  ConsumerState<GameCard> createState() => _GameCardState();
}

class _GameCardState extends ConsumerState<GameCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(rommServiceProvider);
    final finalCoverUrl = service?.resolveCoverUrl(widget.game);

    return ExcludeSemantics(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
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
                    (finalCoverUrl == null || finalCoverUrl.isEmpty)
                        ? const Center(child: Icon(Icons.sports_esports, size: 48))
                        : Image.network(
                            finalCoverUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            errorBuilder: (context, error, stackTrace) => const Center(
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
              SizedBox(
                height: 90,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!widget.showButtonsOnHover || !_isHovering)
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
                      
                      if (!widget.showButtonsOnHover || _isHovering)
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
