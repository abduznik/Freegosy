import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/romm/romm_models.dart';

class PlatformFilterBar extends StatelessWidget {
  final List<Platform> platforms;
  final int? selectedPlatformId;
  final Function(Platform?) onSelected;

  const PlatformFilterBar({
    super.key,
    required this.platforms,
    required this.selectedPlatformId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAllSelected = selectedPlatformId == null;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: FilterChip(
                label: const Text('All'),
                selected: isAllSelected,
                onSelected: (selected) {
                  if (selected) onSelected(null);
                },
                // Styling for selected 'All' chip
                backgroundColor: isAllSelected ? colorScheme.primary : null,
                labelStyle: TextStyle(
                  color: isAllSelected ? Colors.white : colorScheme.onSurface,
                ),
                side: isAllSelected ? null : BorderSide(color: colorScheme.outline.withOpacity(0.5)),
              ),
            ),
            ...platforms.map((platform) {
              final isSelected = selectedPlatformId == platform.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(platform.name),
                  selected: isSelected,
                  onSelected: (selected) {
                    onSelected(selected ? platform : null);
                  },
                  // Styling for selected platform chip
                  backgroundColor: isSelected ? colorScheme.primary : null,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : colorScheme.onSurface,
                  ),
                  side: isSelected ? null : BorderSide(color: colorScheme.outline.withOpacity(0.5)),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
