import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// The game's screenshot across the top of the game page, as on RomM: dimmed
/// enough for the title and buttons on top of it to stay readable, and
/// fading into the page background further down.
class GameBanner extends StatelessWidget {
  const GameBanner({super.key, required this.imageUrl, required this.height});

  final String imageUrl;
  final double height;

  /// 45% of the window, kept between 260 and 420 px.
  static double heightFor(double windowHeight) => (windowHeight * 0.45).clamp(260.0, 420.0);

  @override
  Widget build(BuildContext context) {
    final page = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover, errorWidget: (_, _, _) => const SizedBox()),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [page.withValues(alpha: 0.35), page.withValues(alpha: 0.6), page.withValues(alpha: 0.88), page],
                stops: const [0, 0.45, 0.8, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
