import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/romm/romm_models.dart';

/// One game in the library's list layout: a small cover, the title and
/// platform, and the details that matter when scanning a long library
/// (size, rating, status, when it was last played, and whether it is downloaded).
class GameListRow extends StatelessWidget {
  final Game game;
  final String? coverUrl;
  final bool isDownloaded;

  const GameListRow({super.key, required this.game, this.coverUrl, this.isDownloaded = false});

  static const statusLabels = {
    'incomplete': 'Playing',
    'finished': 'Finished',
    'completed_100': '100%',
    'retired': 'Dropped',
    'never_playing': 'Never playing',
  };

  static String sizeLabel(int bytes) {
    const gb = 1024 * 1024 * 1024, mb = 1024 * 1024;
    if (bytes <= 0) return '';
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    if (bytes >= mb) return '${(bytes / mb).round()} MB';
    return '${(bytes / 1024).round()} KB';
  }

  static String agoLabel(DateTime when, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(when);
    if (d.inDays < 1) return 'today';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 30) return '${d.inDays}d ago';
    if (d.inDays < 365) return '${d.inDays ~/ 30}mo ago';
    return '${d.inDays ~/ 365}y ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final details = <Widget>[
      if (sizeLabel(game.fileSize).isNotEmpty) _detail(Icons.sd_storage_outlined, sizeLabel(game.fileSize), muted),
      if (game.userRating > 0) _detail(Icons.star, '${game.userRating}/10', Colors.amber),
      if (statusLabels[game.status] != null) _detail(Icons.flag_outlined, statusLabels[game.status]!, muted),
      if (game.lastPlayed != null) _detail(Icons.history, agoLabel(game.lastPlayed!.toLocal()), muted),
    ];
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        height: 72,
        child: Row(
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: (coverUrl == null || coverUrl!.isEmpty)
                  ? const Center(child: Icon(Icons.sports_esports))
                  : CachedNetworkImage(
                      imageUrl: coverUrl!,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      memCacheWidth: 120,
                      errorWidget: (context, url, error) => const Center(child: Icon(Icons.sports_esports)),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(game.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(game.platformDisplayName ?? game.platformSlug ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(height: 4),
                  // Wraps (and clips) on narrow windows instead of overflowing.
                  Flexible(child: Wrap(spacing: 12, runSpacing: 2, clipBehavior: Clip.hardEdge, children: details)),
                ],
              ),
            ),
            if (isDownloaded)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Tooltip(
                  message: 'Downloaded',
                  child: CircleAvatar(radius: 11, backgroundColor: Colors.green, child: Icon(Icons.check, size: 14, color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _detail(IconData icon, String text, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 11, color: color)),
        ],
      );
}
