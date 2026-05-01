import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../romm/romm_models.dart';

class MetadataCacheService {
  static const String _gamesFile = 'games_cache.json';
  static const String _countsFile = 'platform_counts.json';
  
  List<Game> _cachedGames = [];
  Map<String, int> _platformCounts = {};

  List<Game> get cachedGames => _cachedGames;

  MetadataCacheService();

  Future<String> _getFilePath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$fileName';
  }

  Future<void> load() async {
    try {
      final gamesPath = await _getFilePath(_gamesFile);
      final gamesFile = File(gamesPath);
      if (await gamesFile.exists()) {
        final jsonStr = await gamesFile.readAsString();
        final List<dynamic> decoded = jsonDecode(jsonStr);
        _cachedGames = decoded.map((json) => Game.fromJson(json)).toList();
      }

      final countsPath = await _getFilePath(_countsFile);
      final countsFile = File(countsPath);
      if (await countsFile.exists()) {
        final jsonStr = await countsFile.readAsString();
        _platformCounts = Map<String, int>.from(jsonDecode(jsonStr));
      }
    } catch (e) {
      debugPrint('[MetadataCache] Error loading cache: $e');
      _cachedGames = [];
    }
  }

  Future<void> saveGames(List<Game> games) async {
    // Merge new games with existing cache, avoiding duplicates by ID
    final Map<String, Game> gameMap = {for (var g in _cachedGames) g.id: g};
    for (var g in games) {
      gameMap[g.id] = g;
    }
    _cachedGames = gameMap.values.toList();
    await _persistGames();
  }

  Future<void> updatePlatformCount(String platformId, int count) async {
    _platformCounts[platformId] = count;
    await _persistCounts();
  }

  bool isPlatformValid(String platformId, int remoteCount) {
    return _platformCounts[platformId] == remoteCount;
  }

  Future<void> invalidatePlatform(String platformId) async {
    _cachedGames.removeWhere((g) => g.platformId.toString() == platformId);
    _platformCounts.remove(platformId);
    await _persistGames();
    await _persistCounts();
  }

  Future<void> _persistGames() async {
    try {
      final path = await _getFilePath(_gamesFile);
      final jsonStr = jsonEncode(_cachedGames.map((g) => g.toJson()).toList());
      await File(path).writeAsString(jsonStr);
    } catch (e) {
      debugPrint('[MetadataCache] Error persisting games: $e');
    }
  }

  Future<void> _persistCounts() async {
    try {
      final path = await _getFilePath(_countsFile);
      await File(path).writeAsString(jsonEncode(_platformCounts));
    } catch (e) {
      debugPrint('[MetadataCache] Error persisting counts: $e');
    }
  }

  List<Game> getOfflineGames({
    String? platformId,
    String? search,
    List<String>? genres,
    List<String>? regions,
    List<String>? languages,
  }) {
    return _cachedGames.where((game) {
      // Platform filter
      if (platformId != null && game.platformId.toString() != platformId) {
        return false;
      }

      // Search filter
      if (search != null && search.isNotEmpty) {
        final query = search.toLowerCase();
        if (!game.name.toLowerCase().contains(query) &&
            !(game.platformDisplayName?.toLowerCase().contains(query) ?? false)) {
          return false;
        }
      }

      // Genre filter
      if (genres != null && genres.isNotEmpty) {
        if (!genres.any((g) => game.genres.contains(g))) return false;
      }

      // Region filter
      if (regions != null && regions.isNotEmpty) {
        if (!regions.any((r) => game.regions.contains(r))) return false;
      }

      // Language filter
      if (languages != null && languages.isNotEmpty) {
        if (!languages.any((l) => game.languages.contains(l))) return false;
      }

      return true;
    }).toList();
  }

  Future<void> clear() async {
    _cachedGames = [];
    _platformCounts = {};
    try {
      final gPath = await _getFilePath(_gamesFile);
      final cPath = await _getFilePath(_countsFile);
      final gFile = File(gPath);
      final cFile = File(cPath);
      if (await gFile.exists()) await gFile.delete();
      if (await cFile.exists()) await cFile.delete();
    } catch (_) {}
  }
}
