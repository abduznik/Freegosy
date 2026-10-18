import 'dart:convert';

import '../storage/app_preferences.dart';
import 'active_filters.dart';

/// Named filter + sort combinations the user keeps ("Co-op RPGs", "Backlog
/// shooters"), stored in preferences so the app and headless mode share them.
class SavedFilterStore {
  final AppPreferences _prefs;
  SavedFilterStore(this._prefs);

  static const _key = 'saved_filter_presets';

  /// Saved presets in the order they were created, keyed by name.
  Map<String, ActiveFilters> all() {
    final raw = _prefs.getString(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in decoded.entries)
          if (e.value is Map<String, dynamic>) e.key: ActiveFilters.fromJson(e.value as Map<String, dynamic>),
      };
    } catch (_) {
      return {};
    }
  }

  /// Case-insensitive lookup, so `--saved=co-op` finds "Co-op".
  ActiveFilters? find(String name) {
    final wanted = name.trim().toLowerCase();
    for (final e in all().entries) {
      if (e.key.toLowerCase() == wanted) return e.value;
    }
    return null;
  }

  /// Saves [filters] under [name], replacing a preset with the same name
  /// (compared without regard to case). Returns false for a blank name.
  Future<bool> save(String name, ActiveFilters filters) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final current = all()..removeWhere((k, _) => k.toLowerCase() == trimmed.toLowerCase());
    current[trimmed] = filters;
    await _write(current);
    return true;
  }

  Future<void> delete(String name) async {
    final current = all()..removeWhere((k, _) => k.toLowerCase() == name.trim().toLowerCase());
    await _write(current);
  }

  Future<void> _write(Map<String, ActiveFilters> presets) =>
      _prefs.setString(_key, jsonEncode({for (final e in presets.entries) e.key: e.value.toJson()}));
}
