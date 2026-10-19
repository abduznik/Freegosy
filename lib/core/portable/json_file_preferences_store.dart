import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'portable_paths.dart';

/// `SharedPreferences` storage for a portable copy: one JSON file in the same
/// format as `shared_preferences_windows` (so settings can be copied as a file),
/// written atomically (tmp file + rename) one write at a time, with path values
/// converted by [toStored]/[fromStored] (see [PortablePaths]).
class JsonFilePreferencesStore extends SharedPreferencesStorePlatform {
  JsonFilePreferencesStore(
    this.file, {
    String Function(String)? toStored,
    String Function(String)? fromStored,
    void Function(String message)? onProblem,
    DateTime Function()? now,
  })  : _toStored = toStored ?? _same,
        _fromStored = fromStored ?? _same,
        _onProblem = onProblem ?? ((m) => debugPrint('[Portable] $m')),
        _now = now ?? DateTime.now;

  final io.File file;
  final String Function(String) _toStored;
  final String Function(String) _fromStored;
  final void Function(String message) _onProblem;
  final DateTime Function() _now;

  static String _same(String v) => v;
  static const _defaultPrefix = 'flutter.';

  Map<String, Object>? _cache;
  Future<void> _queue = Future.value();

  io.File get _tmp => io.File('${file.path}.tmp');

  /// [value] with [convert] applied to a path string, or to each path element
  /// of a string list; other values unchanged.
  static Object mapPaths(Object value, String Function(String) convert) {
    if (value is String) {
      return PortablePaths.isDrivePath(value) || value.startsWith(PortablePaths.prefix) ? convert(value) : value;
    }
    if (value is List) return <String>[for (final v in value.cast<String>()) mapPaths(v, convert) as String];
    return value;
  }

  Map<String, Object> _decode(String text) {
    final raw = jsonDecode(text) as Map<String, dynamic>;
    return {
      for (final e in raw.entries)
        if (e.value != null) e.key: mapPaths(e.value is List ? List<String>.from(e.value as List) : e.value as Object, _fromStored),
    };
  }

  /// Reports through `onProblem`, which must never break loading or the
  /// write queue (it may show UI that isn't there yet).
  void _problem(String message) {
    try {
      _onProblem(message);
    } catch (e) {
      debugPrint('[Portable] $message (reporting it failed: $e)');
    }
  }

  Map<String, Object> _load() {
    if (_cache != null) return _cache!;
    if (file.existsSync()) return _cache = _read(file, 'Settings file', main: true);
    if (_tmp.existsSync()) return _cache = _read(_tmp, 'Temporary settings file', main: false);
    return _cache = {};
  }

  /// [f]'s values; empty (after keeping a damaged file aside) when unusable.
  Map<String, Object> _read(io.File f, String what, {required bool main}) {
    final String text;
    try {
      text = f.readAsStringSync();
    } on FormatException {
      return _setAside(f, what); // Encoding error (e.g. invalid UTF-8).
    } on io.FileSystemException catch (e) {
      _problem('$what could not be read ($e)');
      return {};
    }
    try {
      return _decode(text);
    } catch (e) {
      if (e is FormatException || e is TypeError) return _setAside(f, what);
      if (main) rethrow;
      return {}; // Other decode errors in a leftover .tmp: start empty.
    }
  }

  Map<String, Object> _setAside(io.File f, String what) {
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(_now());
    final aside = p.join(file.parent.path, 'shared_preferences.corrupt-$stamp.json');
    try {
      f.renameSync(aside);
    } on io.FileSystemException catch (e) {
      _problem('$what could not be read ($e)');
      return {};
    }
    _problem('$what was damaged; saved a copy as $aside');
    return {};
  }

  Future<bool> _persist() {
    final done = Completer<bool>();
    _queue = _queue.then((_) async {
      try {
        final encoded = jsonEncode({for (final e in _load().entries) e.key: mapPaths(e.value, _toStored)});
        await file.parent.create(recursive: true);
        await _tmp.writeAsString(encoded, flush: true);
        await _tmp.rename(file.path);
        done.complete(true);
      } catch (e) {
        _problem("Can't save settings — the drive isn't available ($e)");
        done.complete(false);
      }
    });
    return done.future;
  }

  /// The stored value for [key] (with its `flutter.` prefix), read synchronously.
  Object? valueOf(String key) => _load()[key];

  /// Waits for every pending write.
  Future<void> flush() => _queue;

  /// Replaces all values (used when importing settings into a running
  /// portable copy, so a later write can't bring back the old values).
  Future<void> replaceAll(Map<String, Object> values) async {
    _cache = Map<String, Object>.from(values);
    await _persist();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _load()[key] = value is List ? List<String>.from(value) : value;
    return _persist();
  }

  @override
  Future<bool> remove(String key) async {
    _load().remove(key);
    return _persist();
  }

  @override
  Future<bool> clear() => clearWithParameters(ClearParameters(filter: PreferencesFilter(prefix: _defaultPrefix)));

  @override
  Future<bool> clearWithPrefix(String prefix) =>
      clearWithParameters(ClearParameters(filter: PreferencesFilter(prefix: prefix)));

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final filter = parameters.filter;
    _load().removeWhere((key, _) =>
        key.startsWith(filter.prefix) && (filter.allowList == null || filter.allowList!.contains(key)));
    return _persist();
  }

  @override
  Future<Map<String, Object>> getAll() =>
      getAllWithParameters(GetAllParameters(filter: PreferencesFilter(prefix: _defaultPrefix)));

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      getAllWithParameters(GetAllParameters(filter: PreferencesFilter(prefix: prefix)));

  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters parameters) async {
    final filter = parameters.filter;
    return {
      for (final e in _load().entries)
        if (e.key.startsWith(filter.prefix) && (filter.allowList?.contains(e.key) ?? true)) e.key: e.value,
    };
  }
}
