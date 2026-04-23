import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/library_provider.dart';

// Function to build the Library Display section
Widget buildDisplaySection(
  BuildContext context,
  double cardAspectRatio,
  int columnCount,
  double cardSpacing,
  bool showTitle,
  String activePreset,
  WidgetRef ref,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Library Display', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      const Text('Presets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          _presetChip('Windows', 'windows_best', activePreset, ref),
          _presetChip('Steam Deck', 'steamdeck_best', activePreset, ref),
          _presetChip('Cozy', 'cozy', activePreset, ref),
          _presetChip('Compact', 'compact', activePreset, ref),
          _presetChip('Custom', 'custom', activePreset, ref),
        ],
      ),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Columns per row', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          Text('$columnCount', style: const TextStyle(fontSize: 16, color: Colors.deepPurple)),
        ],
      ),
      Slider(
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
      const SizedBox(height: 16),
      const Text('Card Shape', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      SegmentedButton<double>(
        segments: const [
          ButtonSegment(value: 1.0, label: Text('Square')),
          ButtonSegment(value: 0.72, label: Text('Portrait')),
          ButtonSegment(value: 0.58, label: Text('Tall')),
        ],
        selected: {
          [1.0, 0.72, 0.58].reduce((a, b) =>
              (a - cardAspectRatio).abs() < (b - cardAspectRatio).abs()
                  ? a
                  : b)
        },
        onSelectionChanged: (selection) {
          ref.read(activePresetProvider.notifier).update('custom');
          ref.read(cardAspectRatioProvider.notifier).update(selection.first);
        },
      ),
      const SizedBox(height: 16),
      const Text('Card Spacing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      SegmentedButton<double>(
        segments: const [
          ButtonSegment(value: 4.0, label: Text('Tight')),
          ButtonSegment(value: 8.0, label: Text('Normal')),
          ButtonSegment(value: 12.0, label: Text('Airy')),
        ],
        selected: {
          [4.0, 8.0, 12.0].reduce((a, b) =>
              (a - cardSpacing).abs() < (b - cardSpacing).abs() ? a : b)
        },
        onSelectionChanged: (selection) {
          ref.read(activePresetProvider.notifier).update('custom');
          ref.read(cardSpacingProvider.notifier).update(selection.first);
        },
      ),
      const SizedBox(height: 16),
      SwitchListTile(
        title: const Text('Show game title'),
        subtitle: const Text('Display title text below cover art'),
        value: showTitle,
        contentPadding: EdgeInsets.zero,
        onChanged: (value) {
          ref.read(activePresetProvider.notifier).update('custom');
          ref.read(showTitleProvider.notifier).update(value);
        },
      ),
    ],
  );
}

// Helper widget for preset chips
Widget _presetChip(String label, String presetKey, String activePreset, WidgetRef ref) {
  final isSelected = activePreset == presetKey;
  return FilterChip(
    label: Text(label),
    selected: isSelected,
    onSelected: (selected) {
      if (!selected) return;
      ref.read(activePresetProvider.notifier).update(presetKey);
      
      if (presetKey == 'custom') return;
      
      final preset = kDisplayPresets[presetKey];
      if (preset == null) return;
      
      final cols = preset['columnCount'] as int;
      final ratio = preset['cardAspectRatio'] as double;
      final spacing = preset['cardSpacing'] as double;
      final title = preset['showTitle'] as bool;
      
      ref.read(columnCountProvider.notifier).update(cols);
      ref.read(cardAspectRatioProvider.notifier).update(ratio);
      ref.read(cardSpacingProvider.notifier).update(spacing);
      ref.read(showTitleProvider.notifier).update(title);
    },
  );
}
