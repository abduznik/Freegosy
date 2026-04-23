import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/emulator/custom_emulator_config.dart';
import 'shared_prefs_provider.dart';

class CustomEmulatorsNotifier extends StateNotifier<List<CustomEmulatorConfig>> {
  static const String _storageKey = 'custom_emulators_config';
  final SharedPreferences _prefs;

  CustomEmulatorsNotifier(this._prefs) : super([]) {
    _load();
  }

  void _load() {
    final jsonStr = _prefs.getString(_storageKey);
    if (jsonStr != null) {
      try {
        final List<dynamic> list = json.decode(jsonStr);
        state = list.map((item) => CustomEmulatorConfig.fromJson(item)).toList();
      } catch (e) {
        state = [];
      }
    }
  }

  void _save() {
    final jsonStr = json.encode(state.map((e) => e.toJson()).toList());
    _prefs.setString(_storageKey, jsonStr);
  }

  void addEmulator(CustomEmulatorConfig config) {
    state = [...state, config];
    _save();
  }

  void removeEmulator(String id) {
    state = state.where((e) => e.id != id).toList();
    _save();
  }
}

final customEmulatorsProvider = StateNotifierProvider<CustomEmulatorsNotifier, List<CustomEmulatorConfig>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return CustomEmulatorsNotifier(prefs);
});
