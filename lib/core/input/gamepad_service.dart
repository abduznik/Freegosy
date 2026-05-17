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

class GamepadService {
  final Ref _ref;
  StreamSubscription<GamepadEvent>? _subscription;
  Timer? _scanTimer;
  final Map<String, String> _controllerNames = {};

  GamepadService(this._ref);

  void initialize() async {
    debugPrint('🎮 GamepadService: Starting direct action listener...');
    
    // Load the SDL Database
    await SDLMappingParser.loadDatabase();
    
    _scan();
    _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) => _scan());

    _subscription = Gamepads.events.listen(
      (event) {
        final normalized = _normalize(event);
        
        // --- SMART LOGGING ---
        if (normalized == null && event.value.abs() > 0.5) {
          debugPrint('🎮 UNMAPPED HID [${event.gamepadId}]: ${event.key} = ${event.value}');
        }

        if (normalized != null) {
          _handleAction(normalized);
        }
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

  void _handleAction(NormalizedInput input) {
    if (_ref.read(inputModeProvider) != InputMode.gamepad) {
      if (input.value.abs() > 0.5) {
        debugPrint('🎮 Switching to GAMEPAD mode.');
        _ref.read(inputModeProvider.notifier).state = InputMode.gamepad;
      }
    }

    if (input.value.abs() < 0.5) return;

    // Broadcast the action to all listeners (screens, global handlers)
    inputActionBus.add(input.action);

    // Some actions still require direct focus manipulation for snappy navigation
    switch (input.action) {
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
      case GameAction.horizontalAxis:
        if (input.value < -0.5) {
          _moveFocus(TraversalDirection.left);
        } else if (input.value > 0.5) {
          _moveFocus(TraversalDirection.right);
        }
        break;
      case GameAction.verticalAxis:
        if (input.value < -0.5) {
          _moveFocus(TraversalDirection.up);
        } else if (input.value > 0.5) {
          _moveFocus(TraversalDirection.down);
        }
        break;
      default:
        break;
    }
  }

  void _moveFocus(TraversalDirection direction) {
    FocusManager.instance.primaryFocus?.focusInDirection(direction);
  }

  void dispose() {
    _subscription?.cancel();
    _scanTimer?.cancel();
  }
}
