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
    final theme = Theme.of(context);
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
              ? LinearGradient(
                  colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isPrimary
              ? null
              : (isDestructive
                  ? Colors.red.withValues(alpha: 0.08)
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
          border: Border.all(
            color: isPrimary
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : (isDestructive
                    ? Colors.red.withValues(alpha: 0.2)
                    : theme.colorScheme.outline.withValues(alpha: 0.3)),
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
                  ? theme.colorScheme.onPrimary
                  : (isDestructive ? Colors.redAccent : theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isPrimary ? 15 : 12,
                  fontWeight: isPrimary ? FontWeight.bold : FontWeight.w600,
                  color: isPrimary
                      ? theme.colorScheme.onPrimary
                      : (isDestructive ? Colors.redAccent : theme.colorScheme.onSurface.withValues(alpha: 0.9)),
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
