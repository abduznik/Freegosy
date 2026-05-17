import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/romm/romm_models.dart';
import 'focus_effect_wrapper.dart';


class PlatformFilterBar extends StatelessWidget {
  final List<Platform> platforms;
  final int? selectedPlatformId;
  final bool isHome;
  final FocusNode? focusNode;
  final FocusNode? firstChipFocusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final Function(Platform?) onSelected;
  final VoidCallback onHomeSelected;

  const PlatformFilterBar({
    super.key,
    required this.platforms,
    required this.selectedPlatformId,
    required this.isHome,
    this.focusNode,
    this.firstChipFocusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    required this.onSelected,
    required this.onHomeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isAllSelected = selectedPlatformId == null && !isHome;

    return Focus(
      focusNode: focusNode,
      skipTraversal: false, 
      onKeyEvent: (node, event) {
        if (event is! KeyUpEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            onNavigateDown?.call();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            onNavigateUp?.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip(
                  context,
                  label: 'Home',
                  isSelected: isHome,
                  onSelected: (_) => onHomeSelected(),
                  focusNode: firstChipFocusNode,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  context,
                  label: 'All',
                  isSelected: isAllSelected,
                  onSelected: (_) => onSelected(null),
                ),
                ...platforms.map((platform) => Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: _buildFilterChip(
                    context,
                    label: platform.name,
                    isSelected: selectedPlatformId == platform.id,
                    onSelected: (_) => onSelected(platform),
                  ),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required Function(bool) onSelected,
    FocusNode? focusNode,
  }) {
    final theme = Theme.of(context);
    return FocusEffectWrapper(
      onTap: () => onSelected(true),
      borderRadius: 20,
      scaleFactor: 1.1,
      focusNode: focusNode,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
