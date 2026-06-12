import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'gamepad_service.dart';

const _kPrefsKey = 'custom_controller_mappings_v1';

Map<String, Map<String, GameAction>> customControllerMappings = {};

Future<void> loadCustomMappings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null || raw.isEmpty) return;

    final outer = jsonDecode(raw) as Map<String, dynamic>;
    customControllerMappings = outer.map((controllerName, buttons) {
      final btnMap = (buttons as Map<String, dynamic>).map((btnKey, actionName) {
        final action = GameAction.values.firstWhere(
          (a) => a.name == actionName,
          orElse: () => GameAction.confirm,
        );
        return MapEntry(btnKey, action);
      });
      return MapEntry(controllerName, btnMap);
    });
  } catch (e) {
    // Corrupt data — start fresh
    customControllerMappings = {};
  }
}

Future<void> saveCustomMappings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final outer = customControllerMappings.map((controllerName, buttons) {
      final btnMap = buttons.map((btnKey, action) => MapEntry(btnKey, action.name));
      return MapEntry(controllerName, btnMap);
    });
    await prefs.setString(_kPrefsKey, jsonEncode(outer));
  } catch (_) {}
}
