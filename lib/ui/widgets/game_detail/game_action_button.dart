import 'package:flutter/material.dart';
import '../focus_effect_wrapper.dart';

class GameActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final FocusNode? focusNode;

  const GameActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return FocusEffectWrapper(
      focusNode: focusNode,
      onTap: onPressed,
      child: Column(
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
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color ?? Colors.white70,
                ),
          ),
        ],
      ),
    );
  }
}
