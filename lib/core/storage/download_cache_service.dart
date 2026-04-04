import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadCacheService {
  static const String _key = 'downloaded_files_v2';
  Map<String, Set<String>> _cache = {}; // platformSlug -> Set of filenames

  DownloadCacheService();

  Map<String, Set<String>> get filesByPlatform => _cache;

  /// Loads the persisted cache from SharedPreferences.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return;
    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      _cache = decoded.map((key, value) => 
        MapEntry(key, (value as List).map((e) => e.toString()).toSet())
      );
    } catch (_) {}
  }

  /// Updates the cache with a fresh platform map from disk.
  void rescanFromPlatformMap(Map<String, Set<String>> platformMap) {
    _cache = platformMap.map((key, value) => 
      MapEntry(key, value.map((e) => e.toLowerCase()).toSet())
    );
    _save();
  }

  /// Backward compat for flat rescan
  void rescanFromDirectory(Set<String> filenames) {
    // Note: This won't properly map platforms, so we prefer rescanFromPlatformMap
    _cache['unknown'] = Set.from(filenames.map((e) => e.toLowerCase()));
    _save();
  }

  /// Checks if a file is in the cache (any platform).
  bool isDownloaded(String? filename) {
    if (filename == null || filename.isEmpty) return false;
    final normalized = filename.toLowerCase();
    return _cache.values.any((set) => set.contains(normalized));
  }

  /// Adds a file to the cache and persists it.
  Future<void> addFile(String filename, {String platformSlug = 'unknown'}) async {
    final normalized = filename.toLowerCase();
    _cache.putIfAbsent(platformSlug, () => {}).add(normalized);
    await _save();
  }

  /// Removes a file from the cache and persists it.
  Future<void> removeFile(String filename) async {
    final normalized = filename.toLowerCase();
    for (final set in _cache.values) {
      set.remove(normalized);
    }
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, List<String>> toSave = _cache.map((key, value) => 
        MapEntry(key, value.toList())
      );
      await prefs.setString(_key, jsonEncode(toSave));
    } catch (_) {}
  }
}
