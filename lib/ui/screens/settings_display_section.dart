import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
        onChanged: (value) async {
          ref.read(activePresetProvider.notifier).state = 'custom';
          ref.read(columnCountProvider.notifier).state = value.toInt();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('column_count', value.toInt());
          await prefs.setString('active_preset', 'custom');
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
        onSelectionChanged: (selection) async {
          ref.read(activePresetProvider.notifier).state = 'custom';
          ref.read(cardAspectRatioProvider.notifier).state = selection.first;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('card_aspect_ratio', selection.first);
          await prefs.setString('active_preset', 'custom');
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
        onSelectionChanged: (selection) async {
          ref.read(activePresetProvider.notifier).state = 'custom';
          ref.read(cardSpacingProvider.notifier).state = selection.first;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('card_spacing', selection.first);
          await prefs.setString('active_preset', 'custom');
        },
      ),
      const SizedBox(height: 16),
      SwitchListTile(
        title: const Text('Show game title'),
        subtitle: const Text('Display title text below cover art'),
        value: showTitle,
        contentPadding: EdgeInsets.zero,
        onChanged: (value) async {
          ref.read(activePresetProvider.notifier).state = 'custom';
          ref.read(showTitleProvider.notifier).state = value;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('show_title', value);
          await prefs.setString('active_preset', 'custom');
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
    onSelected: (selected) async {
      if (!selected) return;
      ref.read(activePresetProvider.notifier).state = presetKey;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_preset', presetKey);
      if (presetKey == 'custom') return;
      final preset = kDisplayPresets[presetKey];
      if (preset == null) return;
      final cols = preset['columnCount'] as int;
      final ratio = preset['cardAspectRatio'] as double;
      final spacing = preset['cardSpacing'] as double;
      final title = preset['showTitle'] as bool;
      ref.read(columnCountProvider.notifier).state = cols;
      ref.read(cardAspectRatioProvider.notifier).state = ratio;
      ref.read(cardSpacingProvider.notifier).state = spacing;
      ref.read(showTitleProvider.notifier).state = title;
      await prefs.setInt('column_count', cols);
      await prefs.setDouble('card_aspect_ratio', ratio);
      await prefs.setDouble('card_spacing', spacing);
      await prefs.setBool('show_title', title);
    },
  );
}
