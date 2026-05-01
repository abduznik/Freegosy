import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../core/romm/romm_models.dart';
import 'romm_provider.dart';
import 'shared_prefs_provider.dart';

// Old cache functions removed in favor of LibrarySnapshotService and MetadataCacheService

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
  final snapshotService = ref.watch(librarySnapshotServiceProvider);
  ref.watch(isOfflineProvider);
  
  final snapshot = await snapshotService.loadPlatforms();
  
  if (service == null) {
    return snapshot.where((p) => p.gamesCount > 0).toList();
  }

  if (snapshot.isNotEmpty) {
    // Background refresh
    Future.microtask(() async {
      try {
        final fresh = await service.getPlatforms();
        if (fresh.isNotEmpty) {
          await snapshotService.savePlatforms(fresh);
        }
      } catch (_) {}
    });
    return snapshot.where((p) => p.gamesCount > 0).toList();
  }

  final platforms = await service.getPlatforms();
  if (platforms.isNotEmpty) {
    await snapshotService.savePlatforms(platforms);
  }
  return platforms.where((p) => p.gamesCount > 0).toList();
});

final collectionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.watch(rommServiceProvider);
  final snapshotService = ref.watch(librarySnapshotServiceProvider);
  ref.watch(isOfflineProvider);

  final snapshot = await snapshotService.loadCollections();
  
  if (service == null) return snapshot;

  if (snapshot.isNotEmpty) {
    // Background refresh
    Future.microtask(() async {
      try {
        final fresh = await service.getCollections();
        if (fresh.isNotEmpty) {
          await snapshotService.saveCollections(fresh);
        }
      } catch (_) {}
    });
    return snapshot;
  }

  final collections = await service.getCollections();
  if (collections.isNotEmpty) {
    await snapshotService.saveCollections(collections);
  }
  return collections;
});

final allGamesProvider = FutureProvider<List<Game>>((ref) async {
  final service = ref.watch(rommServiceProvider);
  final cacheService = await ref.watch(metadataCacheServiceProvider.future);
  ref.watch(isOfflineProvider);
  
  final selectedPlatformId = ref.watch(selectedPlatformIdProvider);
  final platformIdStr = selectedPlatformId?.toString();

  if (service == null) {
    return cacheService.getOfflineGames(platformId: platformIdStr);
  }

  if (platformIdStr != null) {
    // Check if platform cache is valid
    final platforms = await ref.watch(platformsProvider.future);
    final platform = platforms.firstWhere((p) => p.id.toString() == platformIdStr, orElse: () => Platform(id: 0, name: '', slug: ''));
    
    if (platform.id != 0 && cacheService.isPlatformValid(platformIdStr, platform.gamesCount)) {
      final cached = cacheService.getOfflineGames(platformId: platformIdStr);
      if (cached.isNotEmpty) return cached;
    }

    final games = await service.getAllGames(platformId: platformIdStr);
    if (games.isNotEmpty) {
      await cacheService.saveGames(games);
      await cacheService.updatePlatformCount(platformIdStr, platform.gamesCount);
    }
    return games;
  }

  // General all-games view
  final cached = cacheService.cachedGames;
  if (cached.isNotEmpty) {
    Future.microtask(() async {
      try {
        final fresh = await service.getAllGames();
        if (fresh.isNotEmpty) {
          await cacheService.saveGames(fresh);
        }
      } catch (_) {}
    });
    return cached;
  }

  final games = await service.getAllGames();
  if (games.isNotEmpty) {
    await cacheService.saveGames(games);
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
