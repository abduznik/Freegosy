import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/romm/romm_models.dart';
import 'romm_provider.dart';

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
