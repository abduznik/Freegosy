import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:gamepads/gamepads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ui_provider.dart';
import 'known_controllers.dart';
import 'sdl_parser.dart';
import 'input_action_bus.dart';
import 'custom_controller_mappings.dart';
import 'gamepad_utils.dart';

enum GameAction {
  up, down, left, right,
  confirm, back, detail, favorite,
  verticalAxis, horizontalAxis,
  l1, r1, start, select
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

class GamepadService extends WidgetsBindingObserver {
  final Ref _ref;
  StreamSubscription<GamepadEvent>? _subscription;
  Timer? _scanTimer;
  final Map<String, String> _controllerNames = {};
  final Map<String, AxisState> _axisStates = {};
  final _rawEventController = StreamController<GamepadEvent>.broadcast();
  // Tracks every raw key seen per controller — used to detect backend-handled axes
  final Map<String, Set<String>> _seenRawKeys = {};

  GameAction? _heldDirection;
  Timer? _holdDelayTimer;
  Timer? _holdRepeatTimer;

  bool _appHasFocus = true;

  /// Raw event stream for controller button sniffing (used by setup dialogs).
  Stream<GamepadEvent> get rawEvents => _rawEventController.stream;

  GamepadService(this._ref);

  void initialize() async {
    debugPrint('🎮 GamepadService: Starting direct action listener...');

    // Load custom mappings
    await loadCustomMappings();

    // Load the SDL Database
    await SDLMappingParser.loadDatabase();

    WidgetsBinding.instance.addObserver(this);

    _scan();
    _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) => _scan());

    _subscription = Gamepads.events.listen(
      (event) {
        _handleGamepadEvent(event);
      },
      onError: (err) => debugPrint('🎮 Gamepad Stream Error: $err'),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appHasFocus = state == AppLifecycleState.resumed;
    debugPrint('🎮 GamepadService: App focus changed to $_appHasFocus');
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

  /// Returns a list of detected controllers with their names and IDs.
  List<Map<String, String>> getDetectedControllers() {
    return _controllerNames.entries.map((entry) => {
      'id': entry.key,
      'name': entry.value,
    }).toList();
  }

  /// Tries to automatically find a mapping for a controller.
  /// Returns a record: (source, mapping) where source is 'custom', 'builtin', 'sdl', or null if not found.
  ({String source, Map<String, GameAction> mapping})? tryAutoMap(String controllerId) {
    final name = _controllerNames[controllerId] ?? '';
    if (name.isEmpty) return null;

    // 1. Custom mappings
    for (final entry in customControllerMappings.entries) {
      if (name.toLowerCase().contains(entry.key.toLowerCase())) {
        return (source: 'custom', mapping: Map<String, GameAction>.from(entry.value));
      }
    }

    // 2. SDL Database
    final sdlMapping = SDLMappingParser.getMapping(name);
    if (sdlMapping != null && sdlMapping.isNotEmpty) {
      return (source: 'sdl', mapping: Map<String, GameAction>.from(sdlMapping));
    }

    // 3. Built-in known_controllers — exact/substring first, then fuzzy token match
    final nameLower = name.toLowerCase();
    for (final entry in kControllerMappings.entries) {
      if (nameLower.contains(entry.key.toLowerCase()) ||
          entry.key.toLowerCase().contains(nameLower)) {
        return (source: 'builtin', mapping: Map<String, GameAction>.from(entry.value));
      }
    }

    // Fuzzy token fallback for built-in list
    final inputTokens = GamepadUtils.tokenize(name);
    String? bestBuiltinKey;
    int bestBuiltinScore = 0;
    for (final entry in kControllerMappings.entries) {
      final dbTokens = GamepadUtils.tokenize(entry.key);
      final shared = inputTokens.intersection(dbTokens).length;
      if (shared >= 2 || (shared >= 1 && shared == inputTokens.length)) {
        if (shared > bestBuiltinScore) {
          bestBuiltinScore = shared;
          bestBuiltinKey = entry.key;
        }
      }
    }
    if (bestBuiltinKey != null) {
      return (source: 'builtin', mapping: Map<String, GameAction>.from(kControllerMappings[bestBuiltinKey]!));
    }

    return null;
  }

  /// Returns which GameActions are already handled automatically by the backend
  /// for this controller (POV hat → d-pad, dwZPos → L2/R2, etc.) and should
  /// therefore be excluded from the manual sniff wizard.
  Set<GameAction> getBackendHandledActions(String controllerId) {
    return GamepadUtils.backendHandledActions(_seenRawKeys[controllerId] ?? {});
  }

  /// Returns the current mapping for a specific controller.
  Map<String, GameAction>? getCurrentMapping(String controllerId) {
    final name = _controllerNames[controllerId] ?? '';
    if (name.isEmpty) return null;

    // Check custom mappings first
    for (final entry in customControllerMappings.entries) {
      if (name.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }

    // Check hardcoded mappings
    for (final entry in kControllerMappings.entries) {
      if (name.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }

    // Return default mapping
    return kDefaultMapping;
  }

  /// Updates the custom mapping for a specific controller.
  Future<void> updateCustomMapping(String controllerId, Map<String, GameAction> mapping) async {
    final name = _controllerNames[controllerId] ?? '';
    if (name.isEmpty) return;

    // Update the custom mappings
    customControllerMappings[name] = mapping;

    // Save to persistent storage
    await saveCustomMappings();
  }

  /// Removes the custom mapping for a controller, falling back to SDL/built-in.
  Future<void> clearCustomMapping(String controllerId) async {
    final name = _controllerNames[controllerId] ?? '';
    if (name.isEmpty) return;

    // Find and remove by substring match (same logic as lookup)
    final keysToRemove = customControllerMappings.keys
        .where((k) => name.toLowerCase().contains(k.toLowerCase()) ||
                      k.toLowerCase().contains(name.toLowerCase()))
        .toList();
    for (final k in keysToRemove) {
      customControllerMappings.remove(k);
    }

    await saveCustomMappings();
  }

  Map<String, GameAction> _getMappingFor(String controllerId) {
    final name = _controllerNames[controllerId] ?? '';

    // 1. Try custom mappings first
    for (final entry in customControllerMappings.entries) {
      if (name.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }

    // 2. Try SDL Database (Universal)
    final sdlMapping = SDLMappingParser.getMapping(name);
    if (sdlMapping != null) return sdlMapping;

    // 3. Try our hardcoded known_controllers
    for (final entry in kControllerMappings.entries) {
      if (name.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }

    // 4. Fallback
    return kDefaultMapping;
  }

  NormalizedInput? _normalize(GamepadEvent event) {
    final mapping = _getMappingFor(event.gamepadId);

    // First try a plain key lookup (digital buttons, named keys like dpad_up).
    final directAction = mapping[event.key];
    if (directAction != null) {
      return NormalizedInput(action: directAction, value: event.value);
    }

    // Then try polarity-encoded keys ("key+" / "key-") for axis / hat-switch
    // directions captured by the sniff wizard.
    //   value > 0  → look up "key+"
    //   value < 0  → look up "key-"
    //   value == 0 → axis centered, no action (will be cleared by axis state machine)
    if (event.value != 0) {
      final polarityKey = GamepadUtils.encodeKey(event.key, event.value >= 0 ? 1 : -1);
      final polarAction = mapping[polarityKey];
      if (polarAction != null) {
        return NormalizedInput(action: polarAction, value: event.value);
      }
    }

    // DirectInput legacy axis fallback: dwXPos/dwYPos → analog stick axes
    final key = event.key.toLowerCase();
    if (key == 'dwxpos' || key == 'dwypos' ||
        key == 'dwrpos' || key == 'dwupos' || key == 'dwvpos') {
      // Normalize raw DirectInput axis (0–65535) to -1.0..1.0
      // Raw center is ~32767; treat as signed
      final normalized = (event.value - 32767.0) / 32767.0;
      final isX = key == 'dwxpos';
      return NormalizedInput(
        action: isX ? GameAction.horizontalAxis : GameAction.verticalAxis,
        value: normalized,
      );
    }

    return null;
  }

  List<GameAction> _decodePOV(double rawValue) => GamepadUtils.decodePOV(rawValue);

  // Tracks which POV directions are currently active to detect release
  final Set<GameAction> _activePovDirections = {};

  void _handleGamepadEvent(GamepadEvent event) {
    // Broadcast raw event for sniffing/configuration dialogs (always allow, for setup dialogs)
    _rawEventController.add(event);

    // If app is not focused, skip input processing but allow raw event broadcasting
    if (!_appHasFocus) return;

    // Track all raw keys seen per controller for backend-detection
    _seenRawKeys.putIfAbsent(event.gamepadId, () => {}).add(event.key.toLowerCase());

    // Handle DirectInput POV hat (D-pad reported as angle in hundredths of degrees)
    final keyLower = event.key.toLowerCase();
    if (keyLower == 'dwpov' || keyLower.startsWith('pov') || keyLower.startsWith('hat')) {
      if (_ref.read(inputModeProvider) != InputMode.gamepad) {
        _ref.read(inputModeProvider.notifier).state = InputMode.gamepad;
      }
      final newDirections = _decodePOV(event.value).toSet();
      // Release directions no longer active
      for (final dir in _activePovDirections.difference(newDirections)) {
        _deactivateDirection(dir);
      }
      // Press newly active directions
      for (final dir in newDirections.difference(_activePovDirections)) {
        _triggerAction(dir, 1.0);
        _activateDirection(dir);
      }
      _activePovDirections
        ..clear()
        ..addAll(newDirections);
      return;
    }

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
      // 3. Handle Digital Buttons (including polarity-decoded hat/axis actions)
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
    _rawEventController.close();
    WidgetsBinding.instance.removeObserver(this);
  }
}
