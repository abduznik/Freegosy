import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:gamepads/gamepads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ui_provider.dart';
import 'known_controllers.dart';
import 'sdl_parser.dart';
import 'input_action_bus.dart';

enum GameAction { 
  up, down, left, right, 
  confirm, back, detail, favorite,
  verticalAxis, horizontalAxis,
  l1, r1, l2, r2, start, select
}

class NormalizedInput {
  final GameAction action;
  final double value;
  const NormalizedInput({required this.action, required this.value});
}

final gamepadServiceProvider = Provider<GamepadService>((ref) {
  final service = GamepadService(ref);
  service.initialize();
  return service;
});

class AxisState {
  bool isNegativeActive = false;
  bool isPositiveActive = false;
}

class GamepadService {
  final Ref _ref;
  StreamSubscription<GamepadEvent>? _subscription;
  Timer? _scanTimer;
  final Map<String, String> _controllerNames = {};
  final Map<String, AxisState> _axisStates = {};

  GameAction? _heldDirection;
  Timer? _holdDelayTimer;
  Timer? _holdRepeatTimer;

  GamepadService(this._ref);

  void initialize() async {
    debugPrint('🎮 GamepadService: Starting direct action listener...');
    
    // Load the SDL Database
    await SDLMappingParser.loadDatabase();
    
    _scan();
    _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) => _scan());

    _subscription = Gamepads.events.listen(
      (event) {
        _handleGamepadEvent(event);
      },
      onError: (err) => debugPrint('🎮 Gamepad Stream Error: $err'),
    );
  }

  void _scan() async {
    final controllers = await Gamepads.list();
    for (var c in controllers) {
      if (!_controllerNames.containsKey(c.id)) {
        debugPrint('🎮 GamepadService: New controller detected! [${c.id}] ${c.name}');
        _controllerNames[c.id] = c.name;
      }
    }
  }

  Map<String, GameAction> _getMappingFor(String controllerId) {
    final name = _controllerNames[controllerId] ?? '';
    
    // 1. Try SDL Database first (Universal)
    final sdlMapping = SDLMappingParser.getMapping(name);
    if (sdlMapping != null) return sdlMapping;

    // 2. Try our hardcoded known_controllers
    for (final entry in kControllerMappings.entries) {
      if (name.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }

    // 3. Fallback
    return kDefaultMapping;
  }

  NormalizedInput? _normalize(GamepadEvent event) {
    final mapping = _getMappingFor(event.gamepadId);
    final action = mapping[event.key];
    if (action != null) {
      return NormalizedInput(action: action, value: event.value);
    }
    return null;
  }

  void _handleGamepadEvent(GamepadEvent event) {
    // 1. Switch to Gamepad input mode if significant event occurs
    if (_ref.read(inputModeProvider) != InputMode.gamepad) {
      if (event.value.abs() > 0.5) {
        debugPrint('🎮 Switching to GAMEPAD mode.');
        _ref.read(inputModeProvider.notifier).state = InputMode.gamepad;
      }
    }

    final normalized = _normalize(event);
    
    // --- SMART LOGGING ---
    if (normalized == null && event.value.abs() > 0.5) {
      debugPrint('🎮 UNMAPPED HID [${event.gamepadId}]: ${event.key} = ${event.value}');
    }

    if (normalized == null) return;

    // 2. Handle Axes (Analog Sticks & D-Pad Axes)
    if (normalized.action == GameAction.horizontalAxis || normalized.action == GameAction.verticalAxis) {
      final axisKey = '${event.gamepadId}_${event.key}';
      final state = _axisStates.putIfAbsent(axisKey, () => AxisState());

      // Invert vertical D-pad axis because D-pad UP is positive on macOS, 
      // but analog stick UP is negative. This unifies their behavior.
      final bool isInverted = event.key.contains('dpad') && normalized.action == GameAction.verticalAxis;
      final double adjustedValue = isInverted ? -event.value : event.value;

      // Negative threshold (-0.5)
      if (adjustedValue < -0.5) {
        if (!state.isNegativeActive) {
          state.isNegativeActive = true;
          final mappedAction = (normalized.action == GameAction.horizontalAxis)
              ? GameAction.left
              : GameAction.up;
          _triggerAction(mappedAction, adjustedValue);
          _activateDirection(mappedAction);
        }
      } else if (adjustedValue > -0.15) {
        if (state.isNegativeActive) {
          state.isNegativeActive = false;
          final mappedAction = (normalized.action == GameAction.horizontalAxis)
              ? GameAction.left
              : GameAction.up;
          _deactivateDirection(mappedAction);
        }
      }

      // Positive threshold (0.5)
      if (adjustedValue > 0.5) {
        if (!state.isPositiveActive) {
          state.isPositiveActive = true;
          final mappedAction = (normalized.action == GameAction.horizontalAxis)
              ? GameAction.right
              : GameAction.down;
          _triggerAction(mappedAction, adjustedValue);
          _activateDirection(mappedAction);
        }
      } else if (adjustedValue < 0.15) {
        if (state.isPositiveActive) {
          state.isPositiveActive = false;
          final mappedAction = (normalized.action == GameAction.horizontalAxis)
              ? GameAction.right
              : GameAction.down;
          _deactivateDirection(mappedAction);
        }
      }
    } else {
      // 3. Handle Digital Buttons
      if (event.value.abs() > 0.5) {
        _triggerAction(normalized.action, event.value);
        if (_isDirectionAction(normalized.action)) {
          _activateDirection(normalized.action);
        }
      } else {
        if (_isDirectionAction(normalized.action)) {
          _deactivateDirection(normalized.action);
        }
      }
    }
  }

  bool _isDirectionAction(GameAction action) {
    return action == GameAction.up ||
           action == GameAction.down ||
           action == GameAction.left ||
           action == GameAction.right;
  }

  void _activateDirection(GameAction action) {
    if (_heldDirection == action) return;
    
    _cancelHoldTimers();
    _heldDirection = action;
    
    // Start delay timer for 500ms (half a second)
    _holdDelayTimer = Timer(const Duration(milliseconds: 500), () {
      // After 500ms delay, start repeating every 120ms
      _holdRepeatTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
        if (_heldDirection == action) {
          _triggerAction(action, 1.0);
        } else {
          timer.cancel();
        }
      });
    });
  }

  void _deactivateDirection(GameAction action) {
    if (_heldDirection == action) {
      _cancelHoldTimers();
      _heldDirection = null;
    }
  }

  void _cancelHoldTimers() {
    _holdDelayTimer?.cancel();
    _holdDelayTimer = null;
    _holdRepeatTimer?.cancel();
    _holdRepeatTimer = null;
  }

  void _triggerAction(GameAction action, double value) {
    // Muted to prevent console clutter:
    // debugPrint('🎮 Gamepad Action Triggered: $action (value: $value)');
    // Broadcast the action to all listeners (screens, global handlers)
    inputActionBus.add(action);

    // Snappy navigation via direct focus movement
    if (!_ref.read(navigationLockedProvider)) {
      switch (action) {
        case GameAction.up:
          _moveFocus(TraversalDirection.up);
          break;
        case GameAction.down:
          _moveFocus(TraversalDirection.down);
          break;
        case GameAction.left:
          _moveFocus(TraversalDirection.left);
          break;
        case GameAction.right:
          _moveFocus(TraversalDirection.right);
          break;
        default:
          break;
      }
    }
  }

  void _moveFocus(TraversalDirection direction) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary.context != null) {
      final renderObject = primary.context!.findRenderObject();
      if (renderObject != null && renderObject.attached) {
        primary.focusInDirection(direction);
      }
    }
  }

  void dispose() {
    _subscription?.cancel();
    _scanTimer?.cancel();
    _cancelHoldTimers();
  }
}
