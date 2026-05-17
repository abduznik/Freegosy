import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/library_provider.dart';

InputDecoration _buildInputDecoration(BuildContext context, String label) {
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
    filled: true,
    fillColor: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.primary),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DropdownButtonFormField<String>(
        value: activePreset,
        decoration: _buildInputDecoration(context, 'Preset Layout'),
        items: const [
          DropdownMenuItem(value: 'windows_best', child: Text('Windows')),
          DropdownMenuItem(value: 'steamdeck_best', child: Text('Steam Deck')),
          DropdownMenuItem(value: 'cozy', child: Text('Cozy')),
          DropdownMenuItem(value: 'compact', child: Text('Compact')),
          DropdownMenuItem(value: 'custom', child: Text('Custom')),
        ],
        onChanged: (presetKey) {
          if (presetKey != null) {
            ref.read(activePresetProvider.notifier).update(presetKey);
            if (presetKey == 'custom') return;
            final preset = kDisplayPresets[presetKey];
            if (preset == null) return;
            ref.read(columnCountProvider.notifier).update(preset['columnCount'] as int);
            ref.read(cardAspectRatioProvider.notifier).update(preset['cardAspectRatio'] as double);
            ref.read(cardSpacingProvider.notifier).update(preset['cardSpacing'] as double);
            ref.read(showTitleProvider.notifier).update(preset['showTitle'] as bool);
          }
        },
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<double>(
        value: selectedShape,
        decoration: _buildInputDecoration(context, 'Card Shape'),
        items: const [
          DropdownMenuItem(value: 1.0, child: Text('Square (1:1)')),
          DropdownMenuItem(value: 0.72, child: Text('Portrait (3:4)')),
          DropdownMenuItem(value: 0.58, child: Text('Tall (9:16)')),
        ],
        onChanged: (val) {
          if (val != null) {
            ref.read(activePresetProvider.notifier).update('custom');
            ref.read(cardAspectRatioProvider.notifier).update(val);
          }
        },
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<double>(
        value: selectedSpacing,
        decoration: _buildInputDecoration(context, 'Card Spacing'),
        items: const [
          DropdownMenuItem(value: 4.0, child: Text('Tight (4px)')),
          DropdownMenuItem(value: 8.0, child: Text('Normal (8px)')),
          DropdownMenuItem(value: 12.0, child: Text('Airy (12px)')),
        ],
        onChanged: (val) {
          if (val != null) {
            ref.read(activePresetProvider.notifier).update('custom');
            ref.read(cardSpacingProvider.notifier).update(val);
          }
        },
      ),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Columns per row',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$columnCount',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SliderTheme(
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
      const SizedBox(height: 8),
      SwitchListTile(
        title: const Text('Show game title', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text('Display title text below cover art', style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 12)),
        value: showTitle,
        contentPadding: EdgeInsets.zero,
        activeColor: theme.colorScheme.primary,
        onChanged: (value) {
          ref.read(activePresetProvider.notifier).update('custom');
          ref.read(showTitleProvider.notifier).update(value);
        },
      ),
    ],
  );
}
