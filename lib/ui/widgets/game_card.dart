import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/romm/romm_models.dart';
import '../../providers/romm_provider.dart';

class GameCard extends ConsumerWidget {
  final Game game;
  final VoidCallback onDownload;
  final VoidCallback onLaunch;
  final bool isDownloaded;

  const GameCard({
    super.key,
    required this.game,
    required this.onDownload,
    required this.onLaunch,
    this.isDownloaded = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(rommServiceProvider);
    final finalCoverUrl = service?.resolveCoverUrl(game);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cover image - 75% height approximately
          Expanded(
            flex: 75,
            child: Stack(
              fit: StackFit.expand,
              children: [
                (finalCoverUrl == null || finalCoverUrl.isEmpty)
                    ? const Center(child: Icon(Icons.sports_esports, size: 48))
                    : Image.network(
                        finalCoverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Icon(Icons.sports_esports, size: 48),
                        ),
                      ),
                if (isDownloaded)
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
          // Content - 25% height approximately
          Expanded(
            flex: 25,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                  child: Text(
                    game.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 32,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.download),
                        onPressed: onDownload,
                        tooltip: 'Download',
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 32,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.play_arrow),
                        onPressed: onLaunch,
                        tooltip: 'Launch',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
