import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/input/input_action_bus.dart';
import '../../core/input/gamepad_service.dart';

/// A universal wrapper for Dialog content that listens to the global Action Bus.
/// When the user presses the 'back' button on their controller/gamepad or 'Escape'
/// on their keyboard, this wrapper will automatically pop the active dialog.
class DialogBackBridge extends StatefulWidget {
  final Widget child;
  const DialogBackBridge({super.key, required this.child});

  @override
  State<DialogBackBridge> createState() => _DialogBackBridgeState();
}

class _DialogBackBridgeState extends State<DialogBackBridge> {
  StreamSubscription<GameAction>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = inputActionBus.stream.listen((action) {
      if (action == GameAction.back) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
