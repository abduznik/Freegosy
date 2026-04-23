import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../romm/romm_models.dart';

class MetadataCacheService {
  static const String _gamesKey = 'cached_games_metadata';
  final SharedPreferences _prefs;
  List<Game> _cachedGames = [];

  MetadataCacheService(this._prefs);

  List<Game> get cachedGames => _cachedGames;

  void load() {
    try {
      final jsonStr = _prefs.getString(_gamesKey);
      if (jsonStr == null) return;
      
      final List<dynamic> decoded = jsonDecode(jsonStr);
      _cachedGames = decoded.map((json) => Game.fromJson(json)).toList();
    } catch (_) {
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
    _persist();
  }

  void _persist() {
    try {
      final jsonList = _cachedGames.map((g) => g.toJson()).toList();
      _prefs.setString(_gamesKey, jsonEncode(jsonList));
    } catch (_) {}
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
}
