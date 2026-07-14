import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/input/input_action_bus.dart';
import '../../core/input/gamepad_service.dart';
import '../../providers/ui_provider.dart';

/// A Slider that can be controlled with a gamepad.
///
/// When focused in gamepad mode:
/// - Press Select/Confirm to enter adjustment mode (slider highlights)
/// - D-pad left/right adjusts the value
/// - Press Select/Confirm again to exit adjustment mode (focus moves normally)
class GamepadSlider extends ConsumerStatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const GamepadSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.label,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  ConsumerState<GamepadSlider> createState() => _GamepadSliderState();
}

class _GamepadSliderState extends ConsumerState<GamepadSlider> {
  bool _active = false;
  bool _focused = false;
  StreamSubscription<GameAction>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = inputActionBus.stream.listen(_onAction);
  }

  @override
  void dispose() {
    _sub?.cancel();
    // Make sure we unlock navigation if we were active
    if (_active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(navigationLockedProvider)) {
          ref.read(navigationLockedProvider.notifier).state = false;
        }
      });
    }
    super.dispose();
  }

  void _onAction(GameAction action) {
    if (!_focused) return;
    if (ref.read(inputModeProvider) != InputMode.gamepad) return;

    if (action == GameAction.select || action == GameAction.confirm) {
      setState(() => _active = !_active);
      ref.read(navigationLockedProvider.notifier).state = _active;
      if (_active) {
        _ensureFocused();
      }
    } else if (_active) {
      if (action == GameAction.left || action == GameAction.right) {
        _adjustValue(action == GameAction.right ? 1 : -1);
      }
    }
  }

  void _adjustValue(int direction) {
    final step = widget.divisions != null
        ? (widget.max - widget.min) / widget.divisions!
        : (widget.max - widget.min) / 100;
    final newValue = (widget.value + step * direction)
        .clamp(widget.min, widget.max);
    widget.onChanged(newValue);
  }

  void _ensureFocused() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inputMode = ref.watch(inputModeProvider);
    final showActive = _active && inputMode == InputMode.gamepad;

    return Focus(
      onFocusChange: (hasFocus) {
        setState(() => _focused = hasFocus);
        if (!hasFocus && _active) {
          setState(() => _active = false);
          ref.read(navigationLockedProvider.notifier).state = false;
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showActive)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 12, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Adjusting — press Select to confirm',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: showActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary,
              inactiveTrackColor: theme.colorScheme.outline.withValues(alpha: 0.2),
              thumbColor: showActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary,
              overlayColor: theme.colorScheme.primary.withValues(alpha: 0.15),
              valueIndicatorColor: theme.colorScheme.primary,
              valueIndicatorTextStyle: TextStyle(color: theme.colorScheme.onPrimary),
              thumbShape: showActive
                  ? const RoundSliderThumbShape(enabledThumbRadius: 12)
                  : const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: widget.value,
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              label: widget.label,
              onChanged: widget.onChanged,
              onChangeEnd: widget.onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}
