import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/save/resume_service.dart';
import '../../../core/save/save_state_info.dart';
import '../focus_effect_wrapper.dart';

/// `[⟲ Resume Game · <time> ⚠ | ▾]`: loads [newest], or opens the slot list.
class ResumeSplitButton extends StatelessWidget {
  const ResumeSplitButton({
    super.key,
    required this.newest,
    required this.focusNode,
    required this.onResume,
    required this.onOpenSlots,
  });

  /// Height of both halves; the Play button below uses it too.
  static const double height = 52;

  final ResumeEntry newest;
  final FocusNode focusNode;
  final VoidCallback onResume;
  final VoidCallback onOpenSlots;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = theme.colorScheme.onPrimary;
    final time = DateFormat('d MMM HH:mm').format(newest.savedAt);
    BoxDecoration shape(BorderRadius radius) => BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
          ),
        );
    const mainRadius = BorderRadius.horizontal(left: Radius.circular(16));
    const slotsRadius = BorderRadius.horizontal(right: Radius.circular(16));
    return Row(children: [
      Expanded(
        child: FocusEffectWrapper(
          key: const Key('resume-main'),
          focusNode: focusNode,
          onTap: onResume,
          borderRadiusGeometry: mainRadius,
          scaleFactor: 1.005,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: shape(mainRadius),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.history, color: onPrimary),
              const SizedBox(width: 10),
              Text('Resume Game',
                  style: TextStyle(color: onPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(width: 8),
              Flexible(
                child: Text('· $time',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: onPrimary.withValues(alpha: 0.8), fontSize: 12)),
              ),
              if (newest.compat == StateCompat.mismatch) ...[
                const SizedBox(width: 6),
                const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
              ],
            ]),
          ),
        ),
      ),
      const SizedBox(width: 2),
      FocusEffectWrapper(
        key: const Key('resume-slots'),
        onTap: onOpenSlots,
        borderRadiusGeometry: slotsRadius,
        scaleFactor: 1.005,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: shape(slotsRadius),
          child: Icon(Icons.arrow_drop_down, color: onPrimary),
        ),
      ),
    ]);
  }
}
