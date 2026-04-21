import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/romm/romm_models.dart';
import '../../providers/library_provider.dart';

class GameCard extends ConsumerWidget {
  final Game game;
  final String? coverUrl;
  final String? platformLogoUrl;
  final bool isDownloaded;
  final bool showTitle;

  const GameCard({
    super.key,
    required this.game,
    this.coverUrl,
    this.platformLogoUrl,
    this.isDownloaded = false,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RepaintBoundary(
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cover image - fills remaining space
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  (coverUrl == null || coverUrl!.isEmpty)
                      ? const Center(child: Icon(Icons.sports_esports, size: 48))
                      : CachedNetworkImage(
                          imageUrl: coverUrl!,
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
                  if (platformLogoUrl != null && platformLogoUrl!.isNotEmpty)
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Consumer(
                            builder: (context, ref, _) {
                              final logoAsync = platformLogoUrl != null && platformLogoUrl!.isNotEmpty
                                  ? ref.watch(platformLogoCacheProvider(platformLogoUrl!))
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
            if (showTitle)
              SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.displayName,
                        maxLines: 1,
                        textAlign: TextAlign.left,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      if (game.platformDisplayName != null)
                        Text(
                          game.platformDisplayName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                ),
              )
            else
              const SizedBox(
                height: 24,
                child: Center(
                  child: Icon(Icons.more_horiz, size: 16, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
