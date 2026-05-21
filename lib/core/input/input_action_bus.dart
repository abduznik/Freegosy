import 'dart:async';
import 'gamepad_service.dart';

/// A global broadcast stream for controller and keyboard actions.
/// Instead of simulating keyboard events, we push high-level actions
/// that screens and widgets can listen to directly.
final inputActionBus = StreamController<GameAction>.broadcast();
