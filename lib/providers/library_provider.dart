import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/romm/romm_models.dart';
import 'romm_provider.dart';

const Map<String, Map<String, dynamic>> kDisplayPresets = {
  'windows_best': {
    'columnCount': 5,
    'cardAspectRatio': 0.56,
    'cardSpacing': 8.0,
    'showTitle': true,
    'showButtonsOnHover': false,
  },
  'steamdeck_best': {
    'columnCount': 3,
    'cardAspectRatio': 0.56,
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
    'cardAspectRatio': 0.56,
    'cardSpacing': 4.0,
    'showTitle': false,
    'showButtonsOnHover': true,
  },
};

final searchQueryProvider = StateProvider<String>((ref) => '');
final selectedPlatformIdProvider = StateProvider<int?>((ref) => null);

final cardAspectRatioProvider = StateProvider<double>((ref) {
  // Synchronous init — actual persisted value is loaded in _loadCardAspectRatio
  // and set via the notifier. Default is 0.72 (square).
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

final platformsProvider = FutureProvider<List<Platform>>((ref) async {
  final service = ref.watch(rommServiceProvider);
  if (service == null) return [];
  return await service.getPlatforms();
});

final allGamesProvider = FutureProvider<List<Game>>((ref) async {
  final service = ref.watch(rommServiceProvider);
  if (service == null) return [];
  return await service.getAllGames();
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
        .where((g) => g.name.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();
  }

  filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return filtered;
});

final retroarchSyncModeProvider = StateProvider<String>((ref) => 'both');

final retroarchSyncModeLoaderProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('retroarch_sync_mode') ?? 'both';
  ref.read(retroarchSyncModeProvider.notifier).state = saved;
});