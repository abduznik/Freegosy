import 'package:flutter/material.dart';

double calculateCardHeight(int columnCount, double cardSpacing,
    double cardAspectRatio, BuildContext context, {bool showTitle = true}) {
  final screenWidth = MediaQuery.of(context).size.width;
  const padding = 24.0;
  final totalSpacing = cardSpacing * (columnCount - 1);
  final cardWidth = (screenWidth - padding - totalSpacing) / columnCount;
  final safeRatio = cardAspectRatio <= 0 ? 0.56 : cardAspectRatio;
  final coverHeight = cardWidth / safeRatio;
  
  // GameCard uses 52 for title or 24 for more_horiz. 
  // We add a bit of extra for the Card's own margin/padding/elevation.
  final footerHeight = showTitle ? 60.0 : 32.0; 
  final totalHeight = coverHeight + footerHeight;
  return totalHeight.clamp(80.0, 900.0);
}

Widget buildSkeletonSliverGrid(
    double cardAspectRatio, int columnCount, double cardSpacing, BuildContext context, {bool showTitle = true}) {
  return SliverPadding(
    padding: const EdgeInsets.all(12),
    sliver: SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnCount,
        crossAxisSpacing: cardSpacing,
        mainAxisSpacing: cardSpacing,
        mainAxisExtent: calculateCardHeight(columnCount, cardSpacing, cardAspectRatio, context, showTitle: showTitle),
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => const _SkeletonCard(),
        childCount: 20,
      ),
    ),
  );
}

Widget buildSkeletonGrid(
    double cardAspectRatio, int columnCount, double cardSpacing, BuildContext context, {bool showTitle = true}) {
  return GridView.builder(
    padding: const EdgeInsets.all(12),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columnCount,
      crossAxisSpacing: cardSpacing,
      mainAxisSpacing: cardSpacing,
      mainAxisExtent: calculateCardHeight(columnCount, cardSpacing, cardAspectRatio, context, showTitle: showTitle),
    ),
    itemCount: 20,
    itemBuilder: (context, index) {
      return const _SkeletonCard();
    },
  );
}

class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) {
      _controller.repeat(reverse: true);
    } else {
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Color.lerp(
              const Color(0xFF1a1a1a),
              const Color(0xFF2a2a2a),
              _animation.value,
            ),
          ),
        );
      },
    );
  }
}