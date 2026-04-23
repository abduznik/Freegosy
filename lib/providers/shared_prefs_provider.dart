import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider that exposes the [SharedPreferences] instance.
/// It must be overridden in the [ProviderScope] during app initialization.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

/// A StateNotifier that automatically persists its state to SharedPreferences.
class PersistentStateNotifier<T> extends StateNotifier<T> {
  final SharedPreferences _prefs;
  final String _key;

  PersistentStateNotifier(this._prefs, this._key, T defaultValue)
      : super(_loadInitialValue(_prefs, _key, defaultValue));

  static T _loadInitialValue<T>(SharedPreferences prefs, String key, T defaultValue) {
    if (defaultValue is int) {
      return (prefs.getInt(key) ?? defaultValue) as T;
    } else if (defaultValue is double) {
      return (prefs.getDouble(key) ?? defaultValue) as T;
    } else if (defaultValue is bool) {
      return (prefs.getBool(key) ?? defaultValue) as T;
    } else if (defaultValue is String) {
      return (prefs.getString(key) ?? defaultValue) as T;
    } else if (defaultValue is List<String>) {
      return (prefs.getStringList(key) ?? defaultValue) as T;
    }
    return defaultValue;
  }

  @override
  set state(T value) {
    super.state = value;
    _saveValue(value);
  }

  /// Updates the state and persists it.
  void update(T value) {
    state = value;
  }

  void _saveValue(T value) {
    if (value is int) {
      _prefs.setInt(_key, value);
    } else if (value is double) {
      _prefs.setDouble(_key, value);
    } else if (value is bool) {
      _prefs.setBool(_key, value);
    } else if (value is String) {
      _prefs.setString(_key, value);
    } else if (value is List<String>) {
      _prefs.setStringList(_key, value);
    }
  }
}

/// Helper function to create a provider for a persistent setting.
StateNotifierProvider<PersistentStateNotifier<T>, T> createPersistentProvider<T>(
  String key,
  T defaultValue,
) {
  return StateNotifierProvider<PersistentStateNotifier<T>, T>((ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return PersistentStateNotifier<T>(prefs, key, defaultValue);
  });
}
