import 'package:flutter/material.dart';

import 'dialog_back_bridge.dart';
import 'focus_effect_wrapper.dart';

Widget _option(BuildContext ctx, String label, Object? result, {bool autofocus = false}) => FocusEffectWrapper(
      autofocus: autofocus,
      onTap: () => Navigator.pop(ctx, result),
      borderRadius: 8,
      useSafeScale: false,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Text(label)),
    );

/// A yes/no question a controller can answer: A runs the focused button
/// (Cancel unless [focusYes]), B cancels.
Future<bool> showControllerConfirm(BuildContext context,
    {required String title, required String body, required String yes, bool focusYes = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => DialogBackBridge(
      child: AlertDialog(
        title: Text(title),
        content: SizedBox(width: 440, child: Text(body)),
        actions: [
          _option(ctx, yes, true, autofocus: focusYes),
          _option(ctx, 'Cancel', false, autofocus: !focusYes),
        ],
      ),
    ),
  );
  return ok == true;
}

/// A list to pick one of [labels] from with a controller; B cancels (null).
Future<int?> showControllerChoice(BuildContext context,
        {required String title, required List<String> labels, int? current, List<bool>? danger}) =>
    showDialog<int>(
      context: context,
      builder: (ctx) => DialogBackBridge(
        child: AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 360,
            child: ListView(shrinkWrap: true, children: [
              for (var i = 0; i < labels.length; i++)
                FocusEffectWrapper(
                  autofocus: i == (current ?? 0),
                  onTap: () => Navigator.pop(ctx, i),
                  borderRadius: 8,
                  useSafeScale: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(labels[i],
                        style: TextStyle(color: (danger?[i] ?? false) ? Colors.redAccent : null)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
