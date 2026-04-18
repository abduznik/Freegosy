import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/emulator/custom_emulator_config.dart';

class CustomEmulatorsNotifier extends StateNotifier<List<CustomEmulatorConfig>> {
  static const String _storageKey = 'custom_emulators_config';

  CustomEmulatorsNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr != null) {
      try {
        final List<dynamic> list = json.decode(jsonStr);
        state = list.map((item) => CustomEmulatorConfig.fromJson(item)).toList();
      } catch (e) {
        state = [];
      }
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(state.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, jsonStr);
  }

  Future<void> addEmulator(CustomEmulatorConfig config) async {
    state = [...state, config];
    await _save();
  }

  Future<void> removeEmulator(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _save();
  }
}

final customEmulatorsProvider = StateNotifierProvider<CustomEmulatorsNotifier, List<CustomEmulatorConfig>>((ref) {
  return CustomEmulatorsNotifier();
});
