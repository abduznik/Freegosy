import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefsKeyGlobal = 'deadzone_global_v1';
const _kPrefsKeyPerController = 'deadzone_per_controller_v1';
const _kPrefsKeyInvertY = 'analog_invert_y_v1';

/// Console-default deadzone values (typical range 0.10–0.25).
/// Xbox One/Series: ~0.23, PS4/PS5: ~0.17, Switch Pro: ~0.15.
/// We default to 0.15 as a good all-round starting point.
const double kDefaultDeadzone = 0.15;
const double kMinDeadzone = 0.0;
const double kMaxDeadzone = 0.50;

/// Global deadzone applied when no per-controller override exists.
double globalDeadzone = kDefaultDeadzone;

/// Per-controller deadzone overrides. Key = controller name (substring match).
Map<String, double> perControllerDeadzone = {};

/// Global Y-axis inversion for analog sticks. Some controllers report
/// positive = up instead of negative = up. Toggle this to fix inverted controls.
bool analogInvertY = false;

/// Loads deadzone settings from SharedPreferences.
Future<void> loadDeadzoneSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    final globalRaw = prefs.getDouble(_kPrefsKeyGlobal);
    if (globalRaw != null) {
      globalDeadzone = globalRaw.clamp(kMinDeadzone, kMaxDeadzone);
    }

    final perRaw = prefs.getString(_kPrefsKeyPerController);
    if (perRaw != null && perRaw.isNotEmpty) {
      final decoded = jsonDecode(perRaw) as Map<String, dynamic>;
      perControllerDeadzone = decoded.map((k, v) {
        final val = (v as num).toDouble().clamp(kMinDeadzone, kMaxDeadzone);
        return MapEntry(k, val);
      });
    }

    analogInvertY = prefs.getBool(_kPrefsKeyInvertY) ?? false;
  } catch (_) {
    globalDeadzone = kDefaultDeadzone;
    perControllerDeadzone = {};
    analogInvertY = false;
  }
}

/// Saves deadzone settings to SharedPreferences.
Future<void> saveDeadzoneSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPrefsKeyGlobal, globalDeadzone);
    final encoded = perControllerDeadzone.map((k, v) => MapEntry(k, v));
    await prefs.setString(_kPrefsKeyPerController, jsonEncode(encoded));
    await prefs.setBool(_kPrefsKeyInvertY, analogInvertY);
  } catch (_) {}
}

/// Returns the effective deadzone for a given controller name.
/// Checks per-controller overrides first (substring match), then global.
double getDeadzoneForController(String controllerName) {
  if (controllerName.isNotEmpty) {
    final lower = controllerName.toLowerCase();
    for (final entry in perControllerDeadzone.entries) {
      if (lower.contains(entry.key.toLowerCase()) ||
          entry.key.toLowerCase().contains(lower)) {
        return entry.value;
      }
    }
  }
  return globalDeadzone;
}

/// Sets the per-controller deadzone override.
Future<void> setPerControllerDeadzone(String controllerName, double value) async {
  final clamped = value.clamp(kMinDeadzone, kMaxDeadzone);
  if (clamped <= globalDeadzone) {
    perControllerDeadzone.removeWhere((k, _) =>
        k.toLowerCase() == controllerName.toLowerCase());
  } else {
    perControllerDeadzone[controllerName] = clamped;
  }
  await saveDeadzoneSettings();
}

/// Sets the global deadzone and updates per-controller overrides that
/// were equal to the old global value.
Future<void> setGlobalDeadzone(double value) async {
  globalDeadzone = value.clamp(kMinDeadzone, kMaxDeadzone);
  await saveDeadzoneSettings();
}

/// Resets all deadzone settings to defaults.
Future<void> resetDeadzoneSettings() async {
  globalDeadzone = kDefaultDeadzone;
  perControllerDeadzone = {};
  analogInvertY = false;
  await saveDeadzoneSettings();
}

/// Applies deadzone to a raw axis value.
/// Returns 0.0 if within the deadzone, otherwise rescales so the edge
/// still reaches ±1.0.
double applyDeadzone(double rawValue, double deadzone) {
  final abs = rawValue.abs();
  if (abs <= deadzone) return 0.0;
  // Rescale: map [deadzone, 1.0] → [0.0, 1.0]
  final sign = rawValue >= 0 ? 1.0 : -1.0;
  return sign * ((abs - deadzone) / (1.0 - deadzone));
}

/// Toggles and persists Y-axis inversion for analog sticks.
Future<void> setAnalogInvertY(bool value) async {
  analogInvertY = value;
  await saveDeadzoneSettings();
}
