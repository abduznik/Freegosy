import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'romm_models.dart';

class LibrarySnapshotService {
  static const String _platformsFile = 'platforms_snapshot.json';
  static const String _collectionsFile = 'collections_snapshot.json';

  Future<String> _getFilePath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$fileName';
  }

  Future<void> savePlatforms(List<Platform> platforms) async {
    try {
      final path = await _getFilePath(_platformsFile);
      final jsonStr = jsonEncode(platforms.map((p) => p.toJson()).toList());
      await File(path).writeAsString(jsonStr);
    } catch (e) {
      debugPrint('[LibrarySnapshot] Error saving platforms: $e');
    }
  }

  Future<List<Platform>> loadPlatforms() async {
    try {
      final path = await _getFilePath(_platformsFile);
      final file = File(path);
      if (!await file.exists()) return [];
      
      final jsonStr = await file.readAsString();
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((json) => Platform.fromJson(json)).toList();
    } catch (e) {
      debugPrint('[LibrarySnapshot] Error loading platforms: $e');
      return [];
    }
  }

  Future<void> saveCollections(List<Map<String, dynamic>> collections) async {
    try {
      final path = await _getFilePath(_collectionsFile);
      final jsonStr = jsonEncode(collections);
      await File(path).writeAsString(jsonStr);
    } catch (e) {
      debugPrint('[LibrarySnapshot] Error saving collections: $e');
    }
  }

  Future<List<Map<String, dynamic>>> loadCollections() async {
    try {
      final path = await _getFilePath(_collectionsFile);
      final file = File(path);
      if (!await file.exists()) return [];
      
      final jsonStr = await file.readAsString();
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('[LibrarySnapshot] Error loading collections: $e');
      return [];
    }
  }

  Future<void> clear() async {
    try {
      final pPath = await _getFilePath(_platformsFile);
      final cPath = await _getFilePath(_collectionsFile);
      final pFile = File(pPath);
      final cFile = File(cPath);
      if (await pFile.exists()) await pFile.delete();
      if (await cFile.exists()) await cFile.delete();
    } catch (e) {
      debugPrint('[LibrarySnapshot] Error clearing snapshots: $e');
    }
  }
}
