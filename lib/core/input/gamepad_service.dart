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
import 'deadzone_config.dart';

enum GameAction {
  up, down, left, right,
  confirm, confirmHold, back, detail, favorite,
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
  GameAction? heldDirection;
  Timer? holdDelayTimer;
  Timer? holdRepeatTimer;
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

  // Debounce for digital buttons to prevent rapid-fire ghost presses
  final Map<GameAction, DateTime> _lastDigitalPress = {};
  static const _digitalDebounce = Duration(milliseconds: 80);

  // Hold detection for non-direction buttons (e.g. confirm)
  final Map<GameAction, DateTime> _buttonDownTime = {};
  Timer? _holdTimer;

  bool _appHasFocus = true;

  /// Raw event stream for controller button sniffing (used by setup dialogs).
  Stream<GamepadEvent> get rawEvents => _rawEventController.stream;

  GamepadService(this._ref);

  void initialize() async {
    debugPrint('[Controller] initialize: starting');

    await loadCustomMappings();
    debugPrint('[Controller] custom mappings loaded');

    await loadDeadzoneSettings();

    await SDLMappingParser.loadDatabase();
    debugPrint('[Controller] SDL database loaded');

    WidgetsBinding.instance.addObserver(this);

    _scan();
    _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) => _scan());
    debugPrint('[Controller] scan timer started (3s interval)');

    _subscription = Gamepads.events.listen(
      (event) {
        try {
          _handleGamepadEvent(event);
        } catch (e) {
          debugPrint('[Controller] event handling error: $e');
        }
      },
      onError: (err) => debugPrint('[Controller] stream error: $err'),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appHasFocus = state == AppLifecycleState.resumed;
    debugPrint('[Controller] app focus changed: $_appHasFocus');
  }

  void _scan() async {
    try {
      final controllers = await Gamepads.list();
      debugPrint('[Controller] scan: found ${controllers.length} controller(s)');
      final currentIds = <String>{};
      for (var c in controllers) {
        currentIds.add(c.id);
        if (!_controllerNames.containsKey(c.id)) {
          debugPrint('[Controller] new controller: [${c.id}] ${c.name}');
          _controllerNames[c.id] = c.name;
        }
      }
      final staleIds = _controllerNames.keys.where((id) => !currentIds.contains(id)).toList();
      for (final id in staleIds) {
        debugPrint('[Controller] disconnected: [${_controllerNames[id]}]');
        _controllerNames.remove(id);
        _axisStates.remove(id);
        _seenRawKeys.remove(id);
      }
      if (staleIds.isNotEmpty) {
        debugPrint('[Controller] cleaned up ${staleIds.length} stale controller(s)');
      }
    } catch (e) {
      debugPrint('[Controller] scan error: $e');
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
    if (name.isEmpty) {
      debugPrint('[Controller] tryAutoMap: no name for controller $controllerId');
      return null;
    }
    debugPrint('[Controller] tryAutoMap: attempting match for "$name"');

    // 1. Custom mappings
    for (final entry in customControllerMappings.entries) {
      if (name.toLowerCase().contains(entry.key.toLowerCase())) {
        debugPrint('[Controller] tryAutoMap: matched custom mapping "${entry.key}"');
        return (source: 'custom', mapping: Map<String, GameAction>.from(entry.value));
      }
    }

    // 2. SDL Database
    final sdlMapping = SDLMappingParser.getMapping(name);
    if (sdlMapping != null && sdlMapping.isNotEmpty) {
      debugPrint('[Controller] tryAutoMap: matched SDL mapping');
      return (source: 'sdl', mapping: Map<String, GameAction>.from(sdlMapping));
    }

    // 3. Built-in known_controllers — exact/substring first, then fuzzy token match
    final nameLower = name.toLowerCase();
    for (final entry in kControllerMappings.entries) {
      if (nameLower.contains(entry.key.toLowerCase()) ||
          entry.key.toLowerCase().contains(nameLower)) {
        debugPrint('[Controller] tryAutoMap: matched builtin "${entry.key}"');
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
      debugPrint('[Controller] tryAutoMap: fuzzy matched builtin "$bestBuiltinKey"');
      return (source: 'builtin', mapping: Map<String, GameAction>.from(kControllerMappings[bestBuiltinKey]!));
    }

    debugPrint('[Controller] tryAutoMap: no match found for "$name"');
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
        debugPrint('[Controller] getCurrentMapping: using custom "${entry.key}"');
        return entry.value;
      }
    }

    // Check hardcoded mappings
    for (final entry in kControllerMappings.entries) {
      if (name.toLowerCase().contains(entry.key.toLowerCase())) {
        debugPrint('[Controller] getCurrentMapping: using hardcoded "${entry.key}"');
        return entry.value;
      }
    }

    // Return default mapping
    debugPrint('[Controller] getCurrentMapping: using default mapping');
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

    // 4. Check if name tokenizes to nothing (Bluetooth filler names)
    final tokens = GamepadUtils.tokenize(name);
    if (tokens.isEmpty && name.isNotEmpty) {
      debugPrint('[Controller] controller "$name" has no recognizable tokens — using default mapping');
    }

    // 5. Fallback
    return kDefaultMapping;
  }

  NormalizedInput? _normalize(GamepadEvent event) {
    final mapping = _getMappingFor(event.gamepadId);

    // First try a plain key lookup (digital buttons, named keys like dpad_up).
    final directAction = mapping[event.key];
    if (directAction != null) {
      debugPrint('[Controller] normalize: key "${event.key}" → ${directAction.name}');
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
        debugPrint('[Controller] normalize: polarity key "$polarityKey" → ${polarAction.name}');
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
      // Apply deadzone to DirectInput axes too
      final controllerName = _controllerNames[event.gamepadId] ?? '';
      final deadzone = getDeadzoneForController(controllerName);
      final withDeadzone = applyDeadzone(normalized, deadzone);
      final isX = key == 'dwxpos';
      debugPrint('[Controller] normalize: DirectInput axis "$key" → ${isX ? "horizontal" : "vertical"}');
      return NormalizedInput(
        action: isX ? GameAction.horizontalAxis : GameAction.verticalAxis,
        value: withDeadzone,
      );
    }

    debugPrint('[Controller] normalize: unmapped key "${event.key}" (value=${event.value})');
    return null;
  }

  List<GameAction> _decodePOV(double rawValue) => GamepadUtils.decodePOV(rawValue);

  // Tracks which POV directions are currently active to detect release
  final Set<GameAction> _activePovDirections = {};

  void _handleGamepadEvent(GamepadEvent event) {
    // Broadcast raw event for sniffing/configuration dialogs (always allow, for setup dialogs)
    if (_rawEventController.isClosed) return;
    _rawEventController.add(event);

    // If app is not focused, skip input processing but allow raw event broadcasting
    if (!_appHasFocus) return;

    debugPrint('[Controller] event: key=${event.key} value=${event.value} id=${event.gamepadId}');

    // Track all raw keys seen per controller for backend-detection
    _seenRawKeys.putIfAbsent(event.gamepadId, () => {}).add(event.key.toLowerCase());

    // Handle DirectInput POV hat (D-pad reported as angle in hundredths of degrees)
    final keyLower = event.key.toLowerCase();
    if (keyLower == 'dwpov' || keyLower.startsWith('pov') || keyLower.startsWith('hat')) {
      if (_ref.read(inputModeProvider) != InputMode.gamepad) {
        debugPrint('[Controller] switching to gamepad mode (POV event)');
        _ref.read(inputModeProvider.notifier).state = InputMode.gamepad;
      }
      final newDirections = _decodePOV(event.value).toSet();
      debugPrint('[Controller] POV directions: $newDirections');
      // Release directions no longer active
      for (final dir in _activePovDirections.difference(newDirections)) {
        _deactivateDirection(dir, 'pov');
      }
      // Press newly active directions
      for (final dir in newDirections.difference(_activePovDirections)) {
        _triggerAction(dir, 1.0);
        _axisStates.putIfAbsent('pov', () => AxisState());
        _activateDirection(dir, 'pov', isDigital: true);
      }
      _activePovDirections
        ..clear()
        ..addAll(newDirections);
      return;
    }

    // 1. Switch to Gamepad input mode if significant event occurs
    if (_ref.read(inputModeProvider) != InputMode.gamepad) {
      if (event.value.abs() > 0.5) {
        debugPrint('[Controller] switching to gamepad mode (axis/button)');
        _ref.read(inputModeProvider.notifier).state = InputMode.gamepad;
      }
    }

    final normalized = _normalize(event);

    if (normalized == null) return;

    // 2. Handle Axes (Analog Sticks & D-Pad Axes)
    if (normalized.action == GameAction.horizontalAxis || normalized.action == GameAction.verticalAxis) {
      final axisKey = '${event.gamepadId}_${event.key}';
      final state = _axisStates.putIfAbsent(axisKey, () => AxisState());
      debugPrint('[Controller] axis: ${normalized.action.name} raw=${event.value}');

      // Invert vertical D-pad axis because D-pad UP is positive on macOS,
      // but analog stick UP is negative. This unifies their behavior.
      // Also apply user Y-axis inversion for analog sticks with flipped axes.
      final bool isDpadInverted = event.key.contains('dpad') && normalized.action == GameAction.verticalAxis;
      final bool isAnalogInverted = analogInvertY && !event.key.contains('dpad') && normalized.action == GameAction.verticalAxis;
      final bool isInverted = isDpadInverted != isAnalogInverted;
      final double rawAdjusted = isInverted ? -event.value : event.value;

      // Apply per-controller deadzone
      final controllerName = _controllerNames[event.gamepadId] ?? '';
      final deadzone = getDeadzoneForController(controllerName);
      // DirectInput axes (dwXpos/dwYpos) are already normalized to -1.0..1.0
      // with deadzone applied in _normalize(). Only apply deadzone here for
      // standard axes that come in as -1.0..1.0 raw values.
      final bool isDirectInput = event.key.toLowerCase().startsWith('dw');
      final double adjustedValue = isDirectInput
          ? normalized.value
          : applyDeadzone(rawAdjusted, deadzone);

      // Deactivation must be checked independently of activation so that
      // crossing from one extreme to the other (e.g. -0.8 → 0.6) properly
      // deactivates the old direction even while the new one activates.
      // Without this, both isNegativeActive and isPositiveActive stay true
      // and the stick appears stuck in one direction.

      // Negative direction
      if (adjustedValue < -0.5) {
        if (!state.isNegativeActive) {
          state.isNegativeActive = true;
          final mappedAction = (normalized.action == GameAction.horizontalAxis)
              ? GameAction.left
              : GameAction.up;
          _triggerAction(mappedAction, adjustedValue);
          _activateDirection(mappedAction, axisKey);
        }
      }
      if (adjustedValue > -0.15) {
        if (state.isNegativeActive) {
          state.isNegativeActive = false;
          final mappedAction = (normalized.action == GameAction.horizontalAxis)
              ? GameAction.left
              : GameAction.up;
          _deactivateDirection(mappedAction, axisKey);
        }
      }

      // Positive direction
      if (adjustedValue > 0.5) {
        if (!state.isPositiveActive) {
          state.isPositiveActive = true;
          final mappedAction = (normalized.action == GameAction.horizontalAxis)
              ? GameAction.right
              : GameAction.down;
          _triggerAction(mappedAction, adjustedValue);
          _activateDirection(mappedAction, axisKey);
        }
      }
      if (adjustedValue < 0.15) {
        if (state.isPositiveActive) {
          state.isPositiveActive = false;
          final mappedAction = (normalized.action == GameAction.horizontalAxis)
              ? GameAction.right
              : GameAction.down;
          _deactivateDirection(mappedAction, axisKey);
        }
      }
    } else {
      // 3. Handle Digital Buttons (including polarity-decoded hat/axis actions)
      if (event.value.abs() > 0.5) {
        // Debounce: ignore repeated presses within the debounce window
        final now = DateTime.now();
        final lastPress = _lastDigitalPress[normalized.action];
        if (lastPress != null && now.difference(lastPress) < _digitalDebounce) {
          return; // Ghost press — skip
        }
        _lastDigitalPress[normalized.action] = now;

        if (_isDirectionAction(normalized.action)) {
          _triggerAction(normalized.action, event.value);
          final digitalKey = 'digital_${normalized.action.name}';
          _axisStates.putIfAbsent(digitalKey, () => AxisState());
          _activateDirection(normalized.action, digitalKey, isDigital: true);
        } else {
          // Non-direction button: track press time for hold detection
          _buttonDownTime[normalized.action] = now;
          _holdTimer?.cancel();
          _holdTimer = Timer(const Duration(milliseconds: 500), () {
            if (_buttonDownTime.containsKey(normalized.action)) {
              // Button held for 500ms — fire hold action
              _buttonDownTime.remove(normalized.action);
              _triggerAction(GameAction.confirmHold, 1.0);
            }
          });
          // Also fire immediate tap (will be superseded by hold if held)
          _triggerAction(normalized.action, event.value);
        }
      } else {
        if (_isDirectionAction(normalized.action)) {
          final digitalKey = 'digital_${normalized.action.name}';
          _deactivateDirection(normalized.action, digitalKey);
        } else {
          // Non-direction button released: cancel hold timer, was a tap
          if (_buttonDownTime.containsKey(normalized.action)) {
            _buttonDownTime.remove(normalized.action);
            _holdTimer?.cancel();
          }
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

  void _activateDirection(GameAction action, String axisKey, {bool isDigital = false}) {
    final state = _axisStates[axisKey];
    if (state == null) return;
    if (state.heldDirection == action) return;

    _cancelAxisTimers(state);
    state.heldDirection = action;

    // Only start repeat timer for digital buttons (d-pad).
    // Analog sticks fire once on threshold crossing — you must re-center
    // and push again to trigger another navigation step.
    if (isDigital) {
      state.holdDelayTimer = Timer(const Duration(milliseconds: 500), () {
        state.holdRepeatTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
          if (state.heldDirection == action && _isAxisStillActive(state, action)) {
            _triggerAction(action, 1.0);
          } else {
            _cancelAxisTimers(state);
            state.heldDirection = null;
          }
        });
      });
    }
  }

  void _deactivateDirection(GameAction action, String axisKey) {
    final state = _axisStates[axisKey];
    if (state == null) return;
    if (state.heldDirection == action) {
      _cancelAxisTimers(state);
      state.heldDirection = null;
    }
  }

  void _cancelAxisTimers(AxisState state) {
    state.holdDelayTimer?.cancel();
    state.holdDelayTimer = null;
    state.holdRepeatTimer?.cancel();
    state.holdRepeatTimer = null;
  }

  bool _isAxisStillActive(AxisState state, GameAction direction) {
    if (direction == GameAction.up || direction == GameAction.left) {
      return state.isNegativeActive;
    }
    return state.isPositiveActive;
  }

  void _triggerAction(GameAction action, double value) {
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
    for (final state in _axisStates.values) {
      _cancelAxisTimers(state);
    }
    _rawEventController.close();
    WidgetsBinding.instance.removeObserver(this);
  }
}
