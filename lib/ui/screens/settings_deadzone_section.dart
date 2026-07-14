import 'package:flutter/material.dart';
import '../../core/input/deadzone_config.dart';
import '../widgets/gamepad_slider.dart';

/// Compact global deadzone row: slider with Off/Default/Max labels.
class DeadzoneGlobalRow extends StatefulWidget {
  const DeadzoneGlobalRow({super.key});

  @override
  State<DeadzoneGlobalRow> createState() => _DeadzoneGlobalRowState();
}

class _DeadzoneGlobalRowState extends State<DeadzoneGlobalRow> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = globalDeadzone;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: GamepadSlider(
                value: _value,
                min: kMinDeadzone,
                max: kMaxDeadzone,
                divisions: 10,
                label: '${(_value * 100).round()}%',
                onChanged: (v) async {
                  setState(() => _value = v);
                  await setGlobalDeadzone(v);
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              child: Text(
                '${(_value * 100).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        Transform.translate(
          offset: const Offset(0, -4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Off',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
              Text(
                'Default: ${(kDefaultDeadzone * 100).round()}%',
                style: TextStyle(
                  fontSize: 9,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
              Text(
                'Max',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
