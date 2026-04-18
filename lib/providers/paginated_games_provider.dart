import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/romm/romm_models.dart';
import 'romm_provider.dart';
import 'downloaded_games_cache_provider.dart';

class ActiveFilters {
  final List<String> genres;
  final List<String> regions;
  final List<String> languages;
  final List<String> collections;
  final List<String> statuses;
  final bool downloadedOnly;
  final bool notDownloadedOnly;

  const ActiveFilters({
    this.genres = const [],
    this.regions = const [],
    this.languages = const [],
    this.collections = const [],
    this.statuses = const [],
    this.downloadedOnly = false,
    this.notDownloadedOnly = false,
  });

  bool get hasActiveFilters =>
      genres.isNotEmpty ||
      regions.isNotEmpty ||
      languages.isNotEmpty ||
      collections.isNotEmpty ||
      statuses.isNotEmpty ||
      downloadedOnly ||
      notDownloadedOnly;

  ActiveFilters copyWith({
    List<String>? genres,
    List<String>? regions,
    List<String>? languages,
    List<String>? collections,
    List<String>? statuses,
    bool? downloadedOnly,
    bool? notDownloadedOnly,
  }) {
    return ActiveFilters(
      genres: genres ?? this.genres,
      regions: regions ?? this.regions,
      languages: languages ?? this.languages,
      collections: collections ?? this.collections,
      statuses: statuses ?? this.statuses,
      downloadedOnly: downloadedOnly ?? this.downloadedOnly,
      notDownloadedOnly: notDownloadedOnly ?? this.notDownloadedOnly,
    );
  }
}

class PaginatedGamesState {
  final List<Game> games;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int total;
  final String? error;

  const PaginatedGamesState({
    this.games = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.total = 0,
    this.error,
  });

  PaginatedGamesState copyWith({
    List<Game>? games,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? total,
    String? error,
  }) =>
      PaginatedGamesState(
        games: games ?? this.games,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        total: total ?? this.total,
        error: error,
      );
}

class PaginatedGamesNotifier extends StateNotifier<PaginatedGamesState> {
  final Ref _ref;
  static const int _pageSize = 50;

  // Per-key cache: key = "$platformId|$search"
  final Map<String, List<Game>> _cache = {};
  final Map<String, int> _offsets = {};
  final Map<String, int> _totals = {};

  String? _currentPlatformId;
  String? _currentSearch;
  ActiveFilters _activeFilters = const ActiveFilters();

  PaginatedGamesNotifier(this._ref) : super(const PaginatedGamesState());

  void setFilters(ActiveFilters filters) {
    _activeFilters = filters;
  }

  String _key(String? platformId, String? search) {
    final filterKey = [
      ..._activeFilters.genres,
      ..._activeFilters.regions,
      ..._activeFilters.languages,
      ..._activeFilters.collections,
      if (_activeFilters.statuses.isNotEmpty) ..._activeFilters.statuses,
    ].join(',');
    return '${platformId ?? "all"}|${search ?? ""}|$filterKey';
  }

  Future<void> loadInitial({String? platformId, String? search}) async {
    _currentPlatformId = platformId;
    _currentSearch = search;
    final key = _key(platformId, search);

    // Serve from cache immediately if available
    if (_cache.containsKey(key)) {
      state = PaginatedGamesState(
        games: _cache[key]!,
        total: _totals[key] ?? _cache[key]!.length,
        hasMore: (_offsets[key] ?? 0) < (_totals[key] ?? 0),
        isLoading: false,
      );
      // Background refresh of first page only
      _backgroundRefresh(platformId: platformId, search: search, key: key);
      return;
    }

    // No cache — show loading and fetch
    state = const PaginatedGamesState(isLoading: true);
    final service = _ref.read(rommServiceProvider);
    
    if (service == null) {
      // Fallback to offline cache
      await _loadOffline(platformId, search);
      return;
    }

    try {
      // SPECIAL CASE: If filtering for 'Downloaded Only', we want it to be "instant"
      // and show everything we've identified on disk.
      if (_activeFilters.downloadedOnly) {
        final downloadedMap = _ref.read(downloadedGamesCacheProvider);
        final metadataCache = _ref.read(metadataCacheServiceProvider).asData?.value;
        
        if (metadataCache != null) {
          // Get all cached metadata
          final allCached = metadataCache.cachedGames;
          
          // Only take those that are actually on disk according to our mapping
          final allDownloaded = allCached.where((g) => downloadedMap[g.id] == true).toList();
          
          // Apply filters locally
          final filtered = allDownloaded.where((game) {
            if (platformId != null && game.platformId.toString() != platformId) return false;
            if (search != null && search.isNotEmpty) {
              final query = search.toLowerCase();
              if (!game.name.toLowerCase().contains(query)) return false;
            }
            return true;
          }).toList();

          state = PaginatedGamesState(
            games: filtered,
            total: filtered.length,
            hasMore: false,
            isLoading: false,
          );
          return;
        }
      }

      final result = await service.getGamesPage(
        offset: 0,
        limit: _pageSize,
        platformId: platformId,
        search: search,
        genres: _activeFilters.genres,
        regions: _activeFilters.regions,
        languages: _activeFilters.languages,
        collections: _activeFilters.collections,
        statuses: _activeFilters.statuses,
      );
      
      // Filter locally for instant response
      List<Game> filteredGames = result.games;
      if (_activeFilters.downloadedOnly || _activeFilters.notDownloadedOnly) {
        final downloadedCache = _ref.read(downloadedGamesCacheProvider);
        filteredGames = result.games.where((game) {
          final isDownloaded = downloadedCache[game.id] ?? false;
          if (_activeFilters.downloadedOnly) return isDownloaded;
          if (_activeFilters.notDownloadedOnly) return !isDownloaded;
          return true;
        }).toList();
      }

      _cache[key] = result.games;
      _offsets[key] = result.games.length;
      _totals[key] = result.total;
      state = PaginatedGamesState(
        games: filteredGames,
        total: result.total,
        hasMore: result.games.length < result.total,
        isLoading: false,
      );

      // Persist results for offline use
      final cacheService = _ref.read(metadataCacheServiceProvider).value;
      if (cacheService != null) {
        await cacheService.saveGames(result.games);
      }
    } catch (e) {
      // On error, also try fallback
      await _loadOffline(platformId, search, error: e.toString());
    }
  }

  Future<void> _loadOffline(String? platformId, String? search, {String? error}) async {
    final cacheService = _ref.read(metadataCacheServiceProvider).value;
    if (cacheService == null) {
      state = state.copyWith(isLoading: false, error: error ?? 'Not connected');
      return;
    }

    final offlineGames = cacheService.getOfflineGames(
      platformId: platformId,
      search: search,
      genres: _activeFilters.genres,
      regions: _activeFilters.regions,
      languages: _activeFilters.languages,
    );

    // Filter by download status locally
    List<Game> filteredOffline = offlineGames;
    if (_activeFilters.downloadedOnly || _activeFilters.notDownloadedOnly) {
      final downloadedCache = _ref.read(downloadedGamesCacheProvider);
      filteredOffline = offlineGames.where((game) {
        final isDownloaded = downloadedCache[game.id] ?? false;
        if (_activeFilters.downloadedOnly) return isDownloaded;
        if (_activeFilters.notDownloadedOnly) return !isDownloaded;
        return true;
      }).toList();
    }

    state = PaginatedGamesState(
      games: filteredOffline,
      total: filteredOffline.length,
      hasMore: false,
      isLoading: false,
      error: error != null ? 'Offline Mode (Server: $error)' : 'Offline Mode',
    );
  }

  Future<void> _backgroundRefresh({
    required String? platformId,
    required String? search,
    required String key,
  }) async {
    final service = _ref.read(rommServiceProvider);
    if (service == null) return;
    try {
      final result = await service.getGamesPage(
        offset: 0,
        limit: _pageSize,
        platformId: platformId,
        search: search,
        genres: _activeFilters.genres,
        regions: _activeFilters.regions,
        languages: _activeFilters.languages,
        collections: _activeFilters.collections,
        statuses: _activeFilters.statuses,
      );
      // Only update if still on same key
      if (_key(_currentPlatformId, _currentSearch) == key) {
        _cache[key] = result.games;
        _offsets[key] = result.games.length;
        _totals[key] = result.total;
        state = PaginatedGamesState(
          games: result.games,
          total: result.total,
          hasMore: result.games.length < result.total,
          isLoading: false,
        );
        
        // Update cache
        final cacheService = _ref.read(metadataCacheServiceProvider).value;
        if (cacheService != null) {
          await cacheService.saveGames(result.games);
        }
      }
    } catch (_) {}
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    final service = _ref.read(rommServiceProvider);
    if (service == null) return;
    final key = _key(_currentPlatformId, _currentSearch);
    final int offset = _offsets[key] ?? state.games.length;
    state = state.copyWith(isLoadingMore: true);
    try {
      final result = await service.getGamesPage(
        offset: offset,
        limit: _pageSize,
        platformId: _currentPlatformId,
        search: _currentSearch,
        genres: _activeFilters.genres,
        regions: _activeFilters.regions,
        languages: _activeFilters.languages,
        collections: _activeFilters.collections,
        statuses: _activeFilters.statuses,
      );
      final merged = [...state.games, ...result.games];
      _cache[key] = merged;
      _offsets[key] = merged.length;
      _totals[key] = result.total;

      // Filter by download status locally
      List<Game> filteredMerged = merged;
      if (_activeFilters.downloadedOnly || _activeFilters.notDownloadedOnly) {
        final downloadedCache = _ref.read(downloadedGamesCacheProvider);
        filteredMerged = merged.where((game) {
          final isDownloaded = downloadedCache[game.id] ?? false;
          if (_activeFilters.downloadedOnly) return isDownloaded;
          if (_activeFilters.notDownloadedOnly) return !isDownloaded;
          return true;
        }).toList();
      }

      state = PaginatedGamesState(
        games: filteredMerged,
        total: result.total,
        hasMore: merged.length < result.total,
        isLoadingMore: false,
      );

      // Update cache
      final cacheService = _ref.read(metadataCacheServiceProvider).value;
      if (cacheService != null) {
        await cacheService.saveGames(result.games);
      }
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  void reset() {
    _cache.clear();
    _offsets.clear();
    _totals.clear();
    _currentPlatformId = null;
    _currentSearch = null;
    state = const PaginatedGamesState();
  }
}

final paginatedGamesProvider =
    StateNotifierProvider<PaginatedGamesNotifier, PaginatedGamesState>((ref) {
  return PaginatedGamesNotifier(ref);
});

final activeFiltersProvider = StateProvider<ActiveFilters>((ref) => const ActiveFilters());

final recentlyPlayedProvider = FutureProvider<List<Game>>((ref) async {
  final service = ref.watch(rommServiceProvider);
  if (service == null) return [];
  return service.getRecentlyPlayed(limit: 15);
});
