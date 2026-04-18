import 'package:hive_flutter/hive_flutter.dart';

class RomMappingService {
  static const String _boxName = 'rom_mappings_v2';
  late Box _box;

  static const String _keyMappings = 'path_to_id';
  static const String _keyMTimes = 'dir_mtimes';
  static const String _keyLastSync = 'last_sync_time';

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  /// Map of FilePath -> RomID
  Map<String, String> getMappings() {
    final data = _box.get(_keyMappings);
    if (data is Map) {
      return Map<String, String>.from(data);
    }
    return {};
  }

  Future<void> saveMappings(Map<String, String> mappings) async {
    await _box.put(_keyMappings, mappings);
  }

  Future<void> updateMapping(String path, String romId) async {
    final mappings = getMappings();
    mappings[path] = romId;
    await saveMappings(mappings);
  }

  /// Map of DirectoryPath -> LastModifiedTimestamp (ms)
  Map<String, int> getMTimes() {
    final data = _box.get(_keyMTimes);
    if (data is Map) {
      return Map<String, int>.from(data);
    }
    return {};
  }

  Future<void> saveMTimes(Map<String, int> mtimes) async {
    await _box.put(_keyMTimes, mtimes);
  }

  int? getLastSyncTime() {
    return _box.get(_keyLastSync) as int?;
  }

  Future<void> setLastSyncTime(int timestamp) async {
    await _box.put(_keyLastSync, timestamp);
  }

  String? getRomIdForPath(String path) {
    return getMappings()[path];
  }

  Future<void> clear() async {
    await _box.clear();
  }
}
