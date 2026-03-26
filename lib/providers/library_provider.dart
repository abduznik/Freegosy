import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../core/romm/romm_models.dart';
import 'romm_provider.dart';

const String _gamesCacheKey = 'cached_games';
const String _platformsCacheKey = 'cached_platforms';
const String _gamesCacheTimeKey = 'cached_games_time';
const String _platformsCacheTimeKey = 'cached_platforms_time';
const int _cacheExpiryDays = 7;
const int _cacheMaxBytes = 10 * 1024 * 1024; // 10MB

Future<bool> _isCacheValid(SharedPreferences prefs, String timeKey) async {
  final savedTime = prefs.getString(timeKey);
  if (savedTime == null) return false;
  final cacheTime = DateTime.tryParse(savedTime);
  if (cacheTime == null) return false;
  return DateTime.now().difference(cacheTime).inDays < _cacheExpiryDays;
}

Future<void> _saveGamesCache(List<Game> games) async {
  final prefs = await SharedPreferences.getInstance();
  final jsonList = games.map((g) => {
    'id': g.id,
    'name': g.name,
    'platform_id': g.platformId,
    'platform_slug': g.platformSlug,
    'platform_display_name': g.platformDisplayName,
    'path_cover_large': g.pathCoverLarge,
    'path_cover_small': g.pathCoverSmall,
    'url_cover': g.urlCover,
    'url_download': g.fileUrl,
    'file_name': g.fileName,
    'fs_name': g.fsName,
    'file_size_bytes': g.fileSize,
    'multi_file_path': g.multiFilePath,
    'has_multiple_files': g.hasMultipleFiles,
  }).toList();
  
  final jsonString = jsonEncode(jsonList);
  final sizeInBytes = jsonString.length; // Use .length for string size in bytes (UTF-8)
  
  if (sizeInBytes > _cacheMaxBytes) {
    // Library too large to cache safely
    // Store a flag so we know caching was skipped
    await prefs.setBool('cache_size_exceeded', true);
    await prefs.remove(_gamesCacheKey);
    await prefs.remove(_gamesCacheTimeKey);
    return;
  }
  
  await prefs.setBool('cache_size_exceeded', false);
  await prefs.setString(_gamesCacheKey, jsonString);
  await prefs.setString(
    _gamesCacheTimeKey, 
    DateTime.now().toIso8601String(),
  );
}

Future<void> _savePlatformsCache(List<Platform> platforms) async {
  final prefs = await SharedPreferences.getInstance();
  final jsonList = platforms.map((p) => {
    'id': p.id,
    'name': p.name,
    'slug': p.slug,
  }).toList();
  await prefs.setString(_platformsCacheKey, jsonEncode(jsonList));
  await prefs.setString(_platformsCacheTimeKey, DateTime.now().toIso8601String());
}

Future<List<Game>?> _loadGamesCache() async {
  final prefs = await SharedPreferences.getInstance();
  
  // If cache was previously skipped due to size, 
  // don't attempt to load
  final sizeExceeded = 
    prefs.getBool('cache_size_exceeded') ?? false;
  if (sizeExceeded) return null;
  
  final isValid = await _isCacheValid(prefs, _gamesCacheTimeKey);
  if (!isValid) return null;
  
  final jsonString = prefs.getString(_gamesCacheKey);
  if (jsonString == null) return null;
  
  try {
    final jsonList = jsonDecode(jsonString) as List<dynamic>;
    return jsonList
        .map((item) => Game.fromJson(item as Map<String, dynamic>))
        .toList();
  } catch (e) {
    return null;
  }
}

Future<List<Platform>?> _loadPlatformsCache() async {
  final prefs = await SharedPreferences.getInstance();
  final isValid = await _isCacheValid(prefs, _platformsCacheTimeKey);
  if (!isValid) return null;
  final jsonString = prefs.getString(_platformsCacheKey);
  if (jsonString == null) return null;
  try {
    final jsonList = jsonDecode(jsonString) as List<dynamic>;
    return jsonList
        .map((item) => Platform.fromJson(item as Map<String, dynamic>))
        .toList();
  } catch (e) {
    return null;
  }
}

const Map<String, Map<String, dynamic>> kDisplayPresets = {
  'windows_best': {
    'columnCount': 5,
    'cardAspectRatio': 0.72,
    'cardSpacing': 8.0,
    'showTitle': true,
    'showButtonsOnHover': false,
  },
  'steamdeck_best': {
    'columnCount': 3,
    'cardAspectRatio': 0.72,
    'cardSpacing': 12.0,
    'showTitle': true,
    'showButtonsOnHover': false,
  },
  'cozy': {
    'columnCount': 4,
    'cardAspectRatio': 0.72,
    'cardSpacing': 8.0,
    'showTitle': true,
    'showButtonsOnHover': false,
  },
  'compact': {
    'columnCount': 7,
    'cardAspectRatio': 1.0,
    'cardSpacing': 4.0,
    'showTitle': false,
    'showButtonsOnHover': true,
  },
};

final searchQueryProvider = StateProvider<String>((ref) => '');
final selectedPlatformIdProvider = StateProvider<int?>((ref) => null);

final cardAspectRatioProvider = StateProvider<double>((ref) {
  // Synchronous init — actual persisted value is loaded in _loadCardAspectRatio
  // and set via the notifier. Default is 0.72 (portrait).
  return 0.72;
});

// Loads persisted card aspect ratio into the provider on startup.
final cardAspectRatioLoaderProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getDouble('card_aspect_ratio');
  if (saved != null) {
    ref.read(cardAspectRatioProvider.notifier).state = saved;
  }
});

// Display Settings Providers
final columnCountProvider = StateProvider<int>((ref) {
  return 4;
});

final columnCountLoaderProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getInt('column_count');
  if (saved != null) {
    ref.read(columnCountProvider.notifier).state = saved;
  }
});

final cardSpacingProvider = StateProvider<double>((ref) {
  return 8.0;
});

final cardSpacingLoaderProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getDouble('card_spacing');
  if (saved != null) {
    ref.read(cardSpacingProvider.notifier).state = saved;
  }
});

final showTitleProvider = StateProvider<bool>((ref) {
  return true;
});

final showTitleLoaderProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getBool('show_title');
  if (saved != null) {
    ref.read(showTitleProvider.notifier).state = saved;
  }
});

final showButtonsOnHoverProvider = StateProvider<bool>((ref) {
  return false;
});

final showButtonsOnHoverLoaderProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getBool('show_buttons_on_hover');
  if (saved != null) {
    ref.read(showButtonsOnHoverProvider.notifier).state = saved;
  }
});

final activePresetProvider = StateProvider<String>((ref) {
  return 'custom';
});

final activePresetLoaderProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('active_preset');
  if (saved != null) {
    ref.read(activePresetProvider.notifier).state = saved;
  }
});

final platformsProvider = FutureProvider<List<Platform>>((ref) async {
  final service = ref.watch(rommServiceProvider);
  if (service == null) return [];

  // Try cache first
  final cached = await _loadPlatformsCache();
  if (cached != null) {
    // Refresh in background
    Future.microtask(() async {
      try {
        final fresh = await service.getPlatforms();
        if (fresh.isNotEmpty) {
          await _savePlatformsCache(fresh);
        }
      } catch (_) {}
    });
    return cached;
  }

  // No valid cache — fetch fresh
  final platforms = await service.getPlatforms();
  if (platforms.isNotEmpty) {
    await _savePlatformsCache(platforms);
  }
  return platforms;
});

final allGamesProvider = FutureProvider<List<Game>>((ref) async {
  final service = ref.watch(rommServiceProvider);
  final selectedPlatformId = ref.watch(selectedPlatformIdProvider);
  if (service == null) return [];

  final platformIdStr = selectedPlatformId?.toString();

  if (platformIdStr != null) {
    try {
      return await service.getAllGames(platformId: platformIdStr);
    } catch (e) {
      return await service.getAllGames();
    }
  }

  // Try cache first — return instantly if valid
  final cached = await _loadGamesCache();
  if (cached != null) {
    // Refresh in background without blocking UI
    Future.microtask(() async {
      try {
        final fresh = await service.getAllGames(platformId: platformIdStr);
        if (fresh.isNotEmpty) {
          await _saveGamesCache(fresh);
        }
      } catch (_) {}
    });
    return cached;
  }

  // No valid cache — fetch fresh and cache result
  final games = await service.getAllGames(platformId: platformIdStr);
  if (games.isNotEmpty) {
    await _saveGamesCache(games);
  }
  return games;
});

final filteredGamesProvider = Provider<List<Game>>((ref) {
  final gamesAsync = ref.watch(allGamesProvider);
  final selectedPlatformId = ref.watch(selectedPlatformIdProvider);
  final searchQuery = ref.watch(searchQueryProvider);
  final games = gamesAsync.asData?.value ?? [];

  List<Game> filtered = selectedPlatformId == null
      ? List<Game>.from(games)
      : games.where((g) => g.platformId == selectedPlatformId).toList();

  if (searchQuery.isNotEmpty) {
    filtered = filtered
        .where((g) =>
            g.displayName.toLowerCase().contains(searchQuery.toLowerCase()) ||
            g.name.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();
  }

  filtered.sort((a, b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  return filtered;
});

final retroarchSyncModeProvider = StateProvider<String>((ref) => 'both');

final retroarchSyncModeLoaderProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('retroarch_sync_mode') ?? 'both';
  ref.read(retroarchSyncModeProvider.notifier).state = saved;
});
