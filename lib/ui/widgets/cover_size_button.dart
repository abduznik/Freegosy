import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/library_provider.dart';
import 'dialog_back_bridge.dart';
import 'focus_effect_wrapper.dart';
import 'gamepad_slider.dart';

/// Library app-bar button that opens a cover-size slider, so the
/// grid can be resized without going through Settings → Display.
///
/// The slider runs small → large covers, i.e. the inverse of the column
/// count it drives ([kMaxColumnCount] columns at its left end).
class CoverSizeButton extends ConsumerWidget {
  const CoverSizeButton({super.key});

  /// Slider position for [columnCount]: 0 is the smallest covers.
  static int sizeStepFor(int columnCount) => kMaxColumnCount - columnCount.clamp(kMinColumnCount, kMaxColumnCount);

  /// Column count for slider position [step].
  static int columnCountFor(int step) => (kMaxColumnCount - step).clamp(kMinColumnCount, kMaxColumnCount);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FocusEffectWrapper(
      borderRadius: 24,
      scaleFactor: 1.1,
      onTap: () => _open(context),
      child: IconButton(
        icon: const Icon(Icons.photo_size_select_large),
        tooltip: 'Cover size',
        onPressed: () => _open(context),
      ),
    );
  }

  void _open(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const DialogBackBridge(child: _CoverSizeDialog()),
    );
  }
}

class _CoverSizeDialog extends ConsumerWidget {
  const _CoverSizeDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columnCount = ref.watch(columnCountProvider);
    const steps = kMaxColumnCount - kMinColumnCount;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Cover size'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_size_select_small, size: 18),
                Expanded(
                  child: GamepadSlider(
                    value: CoverSizeButton.sizeStepFor(columnCount).toDouble(),
                    min: 0,
                    max: steps.toDouble(),
                    divisions: steps,
                    label: '$columnCount per row',
                    onChanged: (value) {
                      final next = CoverSizeButton.columnCountFor(value.round());
                      if (next == columnCount) return;
                      ref.read(activePresetProvider.notifier).update('custom');
                      ref.read(columnCountProvider.notifier).update(next);
                    },
                  ),
                ),
                const Icon(Icons.photo_size_select_large, size: 24),
              ],
            ),
            Text('$columnCount games per row', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
