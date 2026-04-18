import 'package:hive_flutter/hive_flutter.dart';

class RomMappingService {
  static const String _boxName = 'rom_mappings_v2';
  late Box _box;

  // Prefix keys to avoid collisions
  static const String _prefixMapping = 'map_';
  static const String _prefixMTime = 'mtime_';
  static const String _keyLastSync = 'last_sync_time';

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  /// Get all FilePath -> RomID mappings
  Map<String, String> getMappings() {
    final Map<String, String> mappings = {};
    for (var key in _box.keys) {
      if (key is String && key.startsWith(_prefixMapping)) {
        mappings[key.substring(_prefixMapping.length)] = _box.get(key);
      }
    }
    return mappings;
  }

  Future<void> updateMapping(String path, String romId) async {
    await _box.put('$_prefixMapping$path', romId);
  }

  Future<void> removeMapping(String path) async {
    await _box.delete('$_prefixMapping$path');
  }

  /// Map of DirectoryPath -> LastModifiedTimestamp (ms)
  Map<String, int> getMTimes() {
    final Map<String, int> mtimes = {};
    for (var key in _box.keys) {
      if (key is String && key.startsWith(_prefixMTime)) {
        mtimes[key.substring(_prefixMTime.length)] = _box.get(key);
      }
    }
    return mtimes;
  }

  Future<void> updateMTime(String path, int timestamp) async {
    await _box.put('$_prefixMTime$path', timestamp);
  }

  int? getLastSyncTime() {
    return _box.get(_keyLastSync) as int?;
  }

  Future<void> setLastSyncTime(int timestamp) async {
    await _box.put(_keyLastSync, timestamp);
  }

  String? getRomIdForPath(String path) {
    return _box.get('$_prefixMapping$path');
  }

  Future<void> clear() async {
    await _box.clear();
  }
}
