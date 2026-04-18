import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/romm/romm_models.dart';

class PlatformFilterBar extends StatelessWidget {
  final List<Platform> platforms;
  final int? selectedPlatformId;
  final bool downloadedOnly;
  final bool isHome;
  final Function(Platform?) onSelected;
  final Function(bool) onDownloadedToggle;
  final VoidCallback onHomeSelected;

  const PlatformFilterBar({
    super.key,
    required this.platforms,
    required this.selectedPlatformId,
    required this.downloadedOnly,
    required this.isHome,
    required this.onSelected,
    required this.onDownloadedToggle,
    required this.onHomeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAllSelected = selectedPlatformId == null && !isHome;

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                avatar: Icon(
                  Icons.home,
                  size: 16,
                  color: isHome ? Colors.white : colorScheme.primary,
                ),
                label: const Text('Home'),
                selected: isHome,
                onSelected: (selected) {
                  if (selected) onHomeSelected();
                },
                backgroundColor: isHome ? colorScheme.primary : null,
                labelStyle: TextStyle(
                  color: isHome ? Colors.white : colorScheme.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: FilterChip(
                label: const Text('All'),
                selected: isAllSelected,
                onSelected: (selected) {
                  if (selected) onSelected(null);
                },
                backgroundColor: isAllSelected ? colorScheme.primary : null,
                labelStyle: TextStyle(
                  color: isAllSelected ? Colors.white : colorScheme.onSurface,
                ),
                side: isAllSelected ? null : BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: FilterChip(
                avatar: Icon(
                  Icons.download_done,
                  size: 16,
                  color: downloadedOnly ? Colors.white : colorScheme.primary,
                ),
                label: const Text('Downloaded'),
                selected: downloadedOnly,
                onSelected: (selected) {
                  onDownloadedToggle(selected);
                },
                backgroundColor: downloadedOnly ? colorScheme.secondary : null,
                labelStyle: TextStyle(
                  color: downloadedOnly ? Colors.white : colorScheme.onSurface,
                ),
                side: downloadedOnly ? null : BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
              ),
            ),
            ...platforms.map((platform) {
              final isSelected = selectedPlatformId == platform.id && !isHome;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(platform.nameForDisplay),
                  selected: isSelected,
                  onSelected: (selected) {
                    onSelected(selected ? platform : null);
                  },
                  backgroundColor: isSelected ? colorScheme.primary : null,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : colorScheme.onSurface,
                  ),
                  side: isSelected ? null : BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
