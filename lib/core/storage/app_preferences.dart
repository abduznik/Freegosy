/// Minimal key-value preferences store used by core services, matching the
/// subset of `package:shared_preferences`'s `SharedPreferences` API they
/// actually call. Core services depend on this interface instead of the
/// concrete `SharedPreferences` type so a pure-Dart entry point (e.g. a CLI)
/// can supply an implementation that doesn't pull in the Flutter engine —
/// `package:shared_preferences` (and even its platform_interface) imports
/// `package:flutter/foundation.dart`, which is fatal under plain `dart run`.
abstract class AppPreferences {
  String? getString(String key);
  bool? getBool(String key);
  Set<String> getKeys();

  Future<bool> setString(String key, String value);
  Future<bool> setBool(String key, bool value);
  Future<bool> remove(String key);
}
