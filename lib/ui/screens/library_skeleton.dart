import 'package:flutter/material.dart';

double calculateCardHeight(int columnCount, double cardSpacing,
    double cardAspectRatio, BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;
  const padding = 24.0;
  final totalSpacing = cardSpacing * (columnCount - 1);
  final cardWidth = (screenWidth - padding - totalSpacing) / columnCount;
  final safeRatio = cardAspectRatio <= 0 ? 0.56 : cardAspectRatio;
  final coverHeight = cardWidth / safeRatio;
  final totalHeight = coverHeight + 90.0;
  return totalHeight.clamp(100.0, 900.0);
}

Widget buildSkeletonGrid(
    double cardAspectRatio, int columnCount, double cardSpacing, BuildContext context) {
  return GridView.builder(
    padding: const EdgeInsets.all(12),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columnCount,
      crossAxisSpacing: cardSpacing,
      mainAxisSpacing: cardSpacing,
      mainAxisExtent: calculateCardHeight(columnCount, cardSpacing, cardAspectRatio, context),
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