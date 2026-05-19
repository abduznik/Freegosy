import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/library_provider.dart';
import '../widgets/focus_effect_wrapper.dart';
import '../widgets/dialog_back_bridge.dart';

Widget _buildCustomDropdown<T>({
  required BuildContext context,
  required String label,
  required T currentValue,
  required String currentValueLabel,
  required List<Map<String, dynamic>> items,
  required Function(T) onChanged,
}) {
  final theme = Theme.of(context);
  return FocusEffectWrapper(
    onTap: () async {
      final selected = await showDialog<T>(
        context: context,
        builder: (ctx) => DialogBackBridge(
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Select $label'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: items.map((item) {
                final isSelected = item['value'] == currentValue;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: FocusEffectWrapper(
                    onTap: () => Navigator.pop(ctx, item['value']),
                    borderRadius: 16.0,
                    autofocus: isSelected,
                    useSafeScale: false,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: isSelected 
                            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4) 
                            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                        border: Border.all(
                          color: isSelected 
                              ? theme.colorScheme.primary.withValues(alpha: 0.4) 
                              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.check_circle : Icons.radio_button_off,
                            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                            size: 18,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            item['label'] as String,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            actions: [
              FocusEffectWrapper(
                onTap: () => Navigator.pop(ctx),
                borderRadius: 16.0,
                useSafeScale: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                    border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                  ),
                  child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ),
            ],
          ),
        ),
      );
      if (selected != null) {
        onChanged(selected);
      }
    },
    borderRadius: 16.0,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            currentValueLabel,
            style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6), size: 20),
        ],
      ),
    ),
  );
}

Widget _buildCustomToggleRow(
  BuildContext context, {
  required String title,
  required String subtitle,
  required bool value,
  required Function(bool) onChanged,
}) {
  final theme = Theme.of(context);
  return FocusEffectWrapper(
    onTap: () => onChanged(!value),
    borderRadius: 16.0,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 11)),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: value ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: value ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              value ? 'ON' : 'OFF',
              style: TextStyle(
                color: value ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget buildDisplaySection(
  BuildContext context,
  double cardAspectRatio,
  int columnCount,
  double cardSpacing,
  bool showTitle,
  String activePreset,
  WidgetRef ref,
) {
  final theme = Theme.of(context);

  // Find the closest standard shape value for dropdown selection
  final shapes = [1.0, 0.72, 0.58];
  final selectedShape = shapes.reduce((a, b) =>
      (a - cardAspectRatio).abs() < (b - cardAspectRatio).abs() ? a : b);

  // Find the closest standard spacing value for dropdown selection
  final spacings = [4.0, 8.0, 12.0];
  final selectedSpacing = spacings.reduce((a, b) =>
      (a - cardSpacing).abs() < (b - cardSpacing).abs() ? a : b);

  final presetLabels = {
    'windows_best': 'Windows',
    'steamdeck_best': 'Steam Deck',
    'cozy': 'Cozy',
    'compact': 'Compact',
    'custom': 'Custom',
  };

  final shapeLabels = {
    1.0: 'Square (1:1)',
    0.72: 'Portrait (3:4)',
    0.58: 'Tall (9:16)',
  };

  final spacingLabels = {
    4.0: 'Tight (4px)',
    8.0: 'Normal (8px)',
    12.0: 'Airy (12px)',
  };

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildCustomDropdown<String>(
        context: context,
        label: 'Preset Layout',
        currentValue: activePreset,
        currentValueLabel: presetLabels[activePreset] ?? 'Custom',
        items: const [
          {'value': 'windows_best', 'label': 'Windows'},
          {'value': 'steamdeck_best', 'label': 'Steam Deck'},
          {'value': 'cozy', 'label': 'Cozy'},
          {'value': 'compact', 'label': 'Compact'},
          {'value': 'custom', 'label': 'Custom'},
        ],
        onChanged: (presetKey) {
          ref.read(activePresetProvider.notifier).update(presetKey);
          if (presetKey == 'custom') return;
          final preset = kDisplayPresets[presetKey];
          if (preset == null) return;
          ref.read(columnCountProvider.notifier).update(preset['columnCount'] as int);
          ref.read(cardAspectRatioProvider.notifier).update(preset['cardAspectRatio'] as double);
          ref.read(cardSpacingProvider.notifier).update(preset['cardSpacing'] as double);
          ref.read(showTitleProvider.notifier).update(preset['showTitle'] as bool);
        },
      ),
      const SizedBox(height: 12),
      _buildCustomDropdown<double>(
        context: context,
        label: 'Card Shape',
        currentValue: selectedShape,
        currentValueLabel: shapeLabels[selectedShape] ?? 'Portrait (3:4)',
        items: const [
          {'value': 1.0, 'label': 'Square (1:1)'},
          {'value': 0.72, 'label': 'Portrait (3:4)'},
          {'value': 0.58, 'label': 'Tall (9:16)'},
        ],
        onChanged: (val) {
          ref.read(activePresetProvider.notifier).update('custom');
          ref.read(cardAspectRatioProvider.notifier).update(val);
        },
      ),
      const SizedBox(height: 12),
      _buildCustomDropdown<double>(
        context: context,
        label: 'Card Spacing',
        currentValue: selectedSpacing,
        currentValueLabel: spacingLabels[selectedSpacing] ?? 'Normal (8px)',
        items: const [
          {'value': 4.0, 'label': 'Tight (4px)'},
          {'value': 8.0, 'label': 'Normal (8px)'},
          {'value': 12.0, 'label': 'Airy (12px)'},
        ],
        onChanged: (val) {
          ref.read(activePresetProvider.notifier).update('custom');
          ref.read(cardSpacingProvider.notifier).update(val);
        },
      ),
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Columns per row',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$columnCount',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: theme.colorScheme.primary,
            inactiveTrackColor: theme.colorScheme.outline.withValues(alpha: 0.2),
            thumbColor: theme.colorScheme.primary,
            overlayColor: theme.colorScheme.primary.withValues(alpha: 0.15),
            valueIndicatorColor: theme.colorScheme.primary,
            valueIndicatorTextStyle: TextStyle(color: theme.colorScheme.onPrimary),
          ),
          child: Slider(
            value: columnCount.toDouble(),
            min: 2,
            max: 8,
            divisions: 6,
            label: '$columnCount',
            onChanged: (value) {
              ref.read(activePresetProvider.notifier).update('custom');
              ref.read(columnCountProvider.notifier).update(value.toInt());
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      _buildCustomToggleRow(
        context,
        title: 'Show game title',
        subtitle: 'Display title text below cover art',
        value: showTitle,
        onChanged: (value) {
          ref.read(activePresetProvider.notifier).update('custom');
          ref.read(showTitleProvider.notifier).update(value);
        },
      ),
    ],
  );
}
