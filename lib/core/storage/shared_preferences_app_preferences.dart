import 'package:shared_preferences/shared_preferences.dart';
import 'app_preferences.dart';

/// [AppPreferences] backed by the real `shared_preferences` plugin — used by
/// the Flutter app.
class SharedPreferencesAppPreferences implements AppPreferences {
  final SharedPreferences _prefs;

  const SharedPreferencesAppPreferences(this._prefs);

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  Set<String> getKeys() => _prefs.getKeys();

  @override
  Future<bool> setString(String key, String value) => _prefs.setString(key, value);

  @override
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<bool> remove(String key) => _prefs.remove(key);
}
