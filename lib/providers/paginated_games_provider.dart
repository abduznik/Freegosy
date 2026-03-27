import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/romm/romm_models.dart';
import 'romm_provider.dart';

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

  PaginatedGamesNotifier(this._ref) : super(const PaginatedGamesState());

  String _key(String? platformId, String? search) =>
      '${platformId ?? "all"}|${search ?? ""}';

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
      state = state.copyWith(isLoading: false, error: 'Not connected');
      return;
    }
    try {
      final result = await service.getGamesPage(
        offset: 0,
        limit: _pageSize,
        platformId: platformId,
        search: search,
      );
      _cache[key] = result.games;
      _offsets[key] = result.games.length;
      _totals[key] = result.total;
      state = PaginatedGamesState(
        games: result.games,
        total: result.total,
        hasMore: result.games.length < result.total,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
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
      );
      final merged = [...state.games, ...result.games];
      _cache[key] = merged;
      _offsets[key] = merged.length;
      _totals[key] = result.total;
      state = PaginatedGamesState(
        games: merged,
        total: result.total,
        hasMore: merged.length < result.total,
        isLoadingMore: false,
      );
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
