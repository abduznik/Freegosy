import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/romm/romm_models.dart';

class GameDetailScreen extends StatelessWidget {
  final Game game;
  final String rommBaseUrl;
  final bool isDownloaded;
  final VoidCallback onLaunch;
  final VoidCallback onDownload;
  final VoidCallback onPushSaves;
  final VoidCallback onPullSaves;
  final VoidCallback onDelete;

  const GameDetailScreen({
    super.key,
    required this.game,
    required this.rommBaseUrl,
    required this.isDownloaded,
    required this.onLaunch,
    required this.onDownload,
    required this.onPushSaves,
    required this.onPullSaves,
    required this.onDelete,
  });

  void _showScreenshotFullscreen(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: () {}, // prevent tap from closing when tapping image itself
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(),
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.image_not_supported,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _normalizeUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final base = rommBaseUrl.endsWith('/')
        ? rommBaseUrl.substring(0, rommBaseUrl.length - 1)
        : rommBaseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$base$normalizedPath';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final headerHeight = size.height * 0.4;

    String? backgroundUrl;
    if (game.screenshotUrl != null && game.screenshotUrl!.isNotEmpty) {
      backgroundUrl = _normalizeUrl(game.screenshotUrl);
    } else if (game.mergedScreenshots.isNotEmpty) {
      backgroundUrl = _normalizeUrl(game.mergedScreenshots.first);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SECTION 1 - Hero header
            SizedBox(
              height: headerHeight,
              child: Stack(
                children: [
                  // Background Image
                  Positioned.fill(
                    child: backgroundUrl != null
                        ? CachedNetworkImage(
                            imageUrl: backgroundUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: Colors.grey[900]),
                            errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
                          )
                        : Container(color: Colors.grey[900]),
                  ),
                  // Gradient Overlay
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black87,
                            Colors.black,
                          ],
                          stops: [0.5, 0.8, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Back Button
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 16,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  // Content (Cover + Title)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Cover Image
                        Hero(
                          tag: 'game_cover_${game.id}',
                          child: Container(
                            width: 130,
                            height: 180,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: _normalizeUrl(game.pathCoverLarge),
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(color: Colors.grey[800]),
                                errorWidget: (context, url, error) => const Icon(Icons.image_not_supported),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Title and Platform
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                game.name,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (game.platformDisplayName != null)
                                Text(
                                  game.platformDisplayName!,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white70,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SECTION 2 - Action buttons row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (!isDownloaded)
                        _ActionButton(
                          icon: Icons.download,
                          label: 'Download',
                          onPressed: onDownload,
                        )
                      else ...[
                        _ActionButton(
                          icon: Icons.play_arrow,
                          label: 'Play',
                          onPressed: onLaunch,
                        ),
                        _ActionButton(
                          icon: Icons.cloud_upload,
                          label: 'Push',
                          onPressed: onPushSaves,
                        ),
                        _ActionButton(
                          icon: Icons.cloud_download,
                          label: 'Pull',
                          onPressed: onPullSaves,
                        ),
                        _ActionButton(
                          icon: Icons.delete,
                          label: 'Delete',
                          onPressed: onDelete,
                          color: Colors.red,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),

                  // SECTION 3 - Metadata chips row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Genres (first 2)
                      ...game.genres.take(2).map((g) => _MetadataChip(label: g)),
                      // Player Count
                      if (game.playerCount != null && game.playerCount!.isNotEmpty)
                        _MetadataChip(
                          label: game.playerCount!,
                          icon: Icons.people_outline,
                        ),
                      // Average Rating
                      if (game.averageRating != null)
                        _MetadataChip(
                          label: '${game.averageRating!.toStringAsFixed(0)}/100',
                          icon: Icons.star_outline,
                        ),
                      // Release Year
                      if (game.firstReleaseDate != null)
                        _MetadataChip(
                          label: DateTime.fromMillisecondsSinceEpoch(game.firstReleaseDate!).year.toString(),
                          icon: Icons.calendar_today_outlined,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // SECTION 4 - Description
                  Text(
                    'About',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    game.summary ?? 'No description available',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // SECTION 5 - Details grid
                  Text(
                    'Details',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DetailsGrid(game: game),
                  const SizedBox(height: 24),

                  // SECTION 6 - Screenshots
                  if (game.mergedScreenshots.isNotEmpty) ...[
                    Text(
                      'Screenshots',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: game.mergedScreenshots.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final imageUrl = _normalizeUrl(game.mergedScreenshots[index]);
                          return GestureDetector(
                            onTap: () => _showScreenshotFullscreen(context, imageUrl),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                width: 200,
                                height: 120,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(color: Colors.grey[900]),
                                errorWidget: (context, url, error) => const Icon(Icons.image_not_supported),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: onPressed,
          icon: Icon(icon, color: color),
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color ?? Colors.white70),
        ),
      ],
    );
  }
}

class _MetadataChip extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _MetadataChip({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DetailsGrid extends StatelessWidget {
  final Game game;

  const _DetailsGrid({required this.game});

  @override
  Widget build(BuildContext context) {
    final details = <String, String>{};
    if (game.companies.isNotEmpty) details['Developer'] = game.companies.join(', ');
    if (game.regions.isNotEmpty) details['Regions'] = game.regions.join(', ');
    if (game.languages.isNotEmpty) details['Languages'] = game.languages.join(', ');
    if (game.playerCount != null && game.playerCount!.isNotEmpty) details['Players'] = game.playerCount!;

    if (details.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 40,
        crossAxisSpacing: 16,
        mainAxisSpacing: 8,
      ),
      itemCount: details.length,
      itemBuilder: (context, index) {
        final entry = details.entries.elementAt(index);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.key,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            Text(
              entry.value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}
