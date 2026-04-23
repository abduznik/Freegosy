import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/romm/romm_models.dart';
import 'romm_provider.dart';
import 'shared_prefs_provider.dart';

const String _gamesCacheKey = 'cached_games';
const String _platformsCacheKey = 'cached_platforms_v2';
const String _gamesCacheTimeKey = 'cached_games_time';
const String _platformsCacheTimeKey = 'cached_platforms_time';
const int _cacheExpiryDays = 7;

Future<bool> _isCacheValid(SharedPreferences prefs, String timeKey) async {
  final savedTime = prefs.getString(timeKey);
  if (savedTime == null) return false;
  final cacheTime = DateTime.tryParse(savedTime);
  if (cacheTime == null) return false;
  return DateTime.now().difference(cacheTime).inDays < _cacheExpiryDays;
}

Future<List<Game>?> _loadGamesCache(Ref ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
  final sizeExceeded = prefs.getBool('cache_size_exceeded') ?? false;
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

Future<List<Platform>?> _loadPlatformsCache(Ref ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
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
    'columnCount': 6,
    'cardAspectRatio': 0.75,
    'cardSpacing': 12.0,
    'showTitle': true,
  },
  'steamdeck_best': {
    'columnCount': 3,
    'cardAspectRatio': 0.72,
    'cardSpacing': 12.0,
    'showTitle': true,
  },
  'cozy': {
    'columnCount': 4,
    'cardAspectRatio': 0.72,
    'cardSpacing': 8.0,
    'showTitle': true,
  },
  'compact': {
    'columnCount': 7,
    'cardAspectRatio': 1.0,
    'cardSpacing': 4.0,
    'showTitle': false,
  },
};

final searchQueryProvider = StateProvider<String>((ref) => '');
final selectedPlatformIdProvider = StateProvider<int?>((ref) => null);

// Display Settings Providers using PersistentStateNotifier
final cardAspectRatioProvider = createPersistentProvider<double>('card_aspect_ratio', 0.75);
final columnCountProvider = createPersistentProvider<int>('column_count', 6);
final cardSpacingProvider = createPersistentProvider<double>('card_spacing', 12.0);
final showTitleProvider = createPersistentProvider<bool>('show_title', true);
final activePresetProvider = createPersistentProvider<String>('active_preset', 'windows_best');

// Legacy compatibility - redirects for loaders (no longer needed but kept for minimal breaking changes)
final cardAspectRatioLoaderProvider = FutureProvider<void>((ref) async {});
final columnCountLoaderProvider = FutureProvider<void>((ref) async {});
final cardSpacingLoaderProvider = FutureProvider<void>((ref) async {});
final showTitleLoaderProvider = FutureProvider<void>((ref) async {});
final activePresetLoaderProvider = FutureProvider<void>((ref) async {});

final platformsProvider = FutureProvider<List<Platform>>((ref) async {
  final service = ref.watch(rommServiceProvider);
  if (service == null) return [];

  final cached = await _loadPlatformsCache(ref);
  if (cached != null) {
    Future.microtask(() async {
      try {
        final fresh = await service.getPlatforms();
        if (fresh.isNotEmpty) {
          final prefs = ref.read(sharedPreferencesProvider);
          final jsonList = fresh.map((p) => {
            'id': p.id,
            'name': p.name,
            'slug': p.slug,
            'games_count': p.gamesCount,
          }).toList();
          await prefs.setString(_platformsCacheKey, jsonEncode(jsonList));
          await prefs.setString(_platformsCacheTimeKey, DateTime.now().toIso8601String());
        }
      } catch (_) {}
    });
    return cached.where((p) => p.gamesCount > 0).toList();
  }

  final platforms = await service.getPlatforms();
  if (platforms.isNotEmpty) {
    final prefs = ref.read(sharedPreferencesProvider);
    final jsonList = platforms.map((p) => {
      'id': p.id,
      'name': p.name,
      'slug': p.slug,
      'games_count': p.gamesCount,
    }).toList();
    await prefs.setString(_platformsCacheKey, jsonEncode(jsonList));
    await prefs.setString(_platformsCacheTimeKey, DateTime.now().toIso8601String());
  }
  return platforms.where((p) => p.gamesCount > 0).toList();
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

  final cached = await _loadGamesCache(ref);
  if (cached != null) {
    Future.microtask(() async {
      try {
        final fresh = await service.getAllGames(platformId: platformIdStr);
        if (fresh.isNotEmpty) {
           final prefs = ref.read(sharedPreferencesProvider);
           final jsonList = fresh.map((g) => g.toJson()).toList();
           await prefs.setString(_gamesCacheKey, jsonEncode(jsonList));
           await prefs.setString(_gamesCacheTimeKey, DateTime.now().toIso8601String());
        }
      } catch (_) {}
    });
    return cached;
  }

  final games = await service.getAllGames(platformId: platformIdStr);
  if (games.isNotEmpty) {
     final prefs = ref.read(sharedPreferencesProvider);
     final jsonList = games.map((g) => g.toJson()).toList();
     await prefs.setString(_gamesCacheKey, jsonEncode(jsonList));
     await prefs.setString(_gamesCacheTimeKey, DateTime.now().toIso8601String());
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

final retroarchSyncModeProvider = createPersistentProvider<String>('retroarch_sync_mode', 'both');
final rpcs3ArchitectureProvider = createPersistentProvider<String>('rpcs3_macos_architecture', 'x64');
final edenBuildTypeProvider = createPersistentProvider<String>('eden_build_type', 'stable');
final retroarchNdsCoreProvider = createPersistentProvider<String>('retroarch_nds_core', 'melonds');

// Legacy compatibility
final retroarchSyncModeLoaderProvider = FutureProvider<void>((ref) async {});
final rpcs3ArchitectureLoaderProvider = FutureProvider<void>((ref) async {});
final edenBuildTypeLoaderProvider = FutureProvider<void>((ref) async {});
final retroarchNdsCoreLoaderProvider = FutureProvider<void>((ref) async {});

final platformLogoCacheProvider = FutureProvider.family<Uint8List?, String>((ref, logoUrl) async {
  if (logoUrl.isEmpty) return null;
  try {
    final response = await http.get(Uri.parse(logoUrl));
    if (response.statusCode != 200) return null;
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final body = response.body;
    if (!contentType.contains('svg') && !body.trim().startsWith('<svg')) return null;
    final inlined = _inlineSvgStyles(body);
    return Uint8List.fromList(utf8.encode(inlined));
  } catch (_) {
    return null;
  }
});

String _inlineSvgStyles(String svgContent) {
  try {
    final styleRegex = RegExp(r'<style[^>]*>(.*?)</style>', dotAll: true);
    final styleMatch = styleRegex.firstMatch(svgContent);
    if (styleMatch == null) return svgContent;
    final styleBlock = styleMatch.group(1)!;
    final classRegex = RegExp(r'\.([\w-]+)\s*\{([^}]*)\}');
    final classMap = <String, String>{};
    for (final match in classRegex.allMatches(styleBlock)) {
      classMap[match.group(1)!] = match.group(2)!.trim();
    }
    var result = svgContent;
    result = result.replaceAllMapped(
      RegExp(r'class="([^"]+)"'),
      (match) {
        final classes = match.group(1)!.split(RegExp(r'\s+'));
        final combinedStyles = classes
            .map((c) => classMap[c] ?? '')
            .where((s) => s.isNotEmpty)
            .join('; ');
        if (combinedStyles.isEmpty) return '';
        return 'style="$combinedStyles"';
      },
    );
    result = result.replaceAll(styleRegex, '');
    return result;
  } catch (_) {
    return svgContent;
  }
}
