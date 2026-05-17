import 'package:flutter/material.dart';
import '../focus_effect_wrapper.dart';

class GameActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final FocusNode? focusNode;
  final bool isPrimary;

  const GameActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.focusNode,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDestructive = color == Colors.red || color == Colors.redAccent;

    return FocusEffectWrapper(
      focusNode: focusNode,
      onTap: onPressed,
      borderRadius: 16.0,
      scaleFactor: isPrimary ? 1.03 : 1.05,
      child: Container(
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: isPrimary ? 40 : 16,
          vertical: isPrimary ? 14 : 10,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isPrimary
              ? const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isPrimary
              ? null
              : (isDestructive
                  ? Colors.red.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.05)),
          border: Border.all(
            color: isPrimary
                ? Colors.white.withValues(alpha: 0.15)
                : (isDestructive
                    ? Colors.red.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08)),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: isPrimary ? 22 : 16,
              color: isPrimary
                  ? Colors.white
                  : (isDestructive ? Colors.redAccent : Colors.white70),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: isPrimary ? 15 : 12,
                fontWeight: isPrimary ? FontWeight.bold : FontWeight.w600,
                color: isPrimary
                    ? Colors.white
                    : (isDestructive ? Colors.redAccent : Colors.white.withValues(alpha: 0.9)),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
