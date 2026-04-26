import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/library_provider.dart';
import '../../providers/romm_provider.dart';
import '../../providers/paginated_games_provider.dart';
import '../../providers/downloaded_games_cache_provider.dart';
import '../../core/storage/directory_service.dart';
import '../../core/romm/romm_models.dart';
import '../widgets/game_card.dart';
import '../widgets/platform_filter_bar.dart';
import '../widgets/filter_bottom_sheet.dart';
import 'library_skeleton.dart';
import 'game_detail_screen.dart';

import 'library_actions.dart';

import '../../providers/download_provider.dart';

final isHomeSelectedProvider = StateProvider<bool>((ref) => true);

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with LibraryActionsMixin {
  late TextEditingController _searchController;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: ref.read(searchQueryProvider));
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 600) {
      ref.read(paginatedGamesProvider.notifier).loadMore();
    }
  }

  Future<void> _refreshLibrary() async {
    ref.invalidate(platformsProvider);
    ref.read(paginatedGamesProvider.notifier).reset();
    await ref.read(paginatedGamesProvider.notifier).loadInitial(
      platformId: ref.read(selectedPlatformIdProvider)?.toString(),
      search: ref.read(searchQueryProvider).isEmpty ? null : ref.read(searchQueryProvider),
    );
    await ref.read(downloadedGamesCacheProvider.notifier).refresh();
  }

  Future<void> _handleGameTap(BuildContext context, WidgetRef ref, Game game) async {
    final config = ref.read(rommConfigProvider).value;
    final baseUrl = config?.baseUrl ?? '';
    final downloads = ref.read(downloadProvider);
    // CRITICAL: Active download always blocks Playable state
    final isActuallyDownloading = downloads.containsKey(game.id);
    final isDownloaded = (ref.read(downloadedGamesCacheProvider)[game.id] ?? false) && !isActuallyDownloading;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameDetailScreen(
          game: game,
          rommBaseUrl: baseUrl,
          isDownloaded: isDownloaded,
          rommService: ref.read(rommServiceProvider),
          onLaunch: () => handleLaunch(context, ref, game),
          onDownload: () => startDownload(context, ref, game),
          onPushSaves: () => handlePushSaves(context, ref, game),
          onPullSaves: () => handlePullSaves(context, ref, game),
          onDelete: () => handleDeleteRom(context, ref, game),
        ),
      ),
    );
    
    if (mounted) {
      await ref.read(downloadedGamesCacheProvider.notifier).refresh();
    }
  }

  Future<void> _openFilterSheet(BuildContext context, WidgetRef ref) async {
    final currentFilters = ref.read(activeFiltersProvider);
    final collections = await ref.read(rommServiceProvider)?.getCollections() ?? [];

    final games = ref.read(paginatedGamesProvider).games;
    final genres = games.expand((g) => g.genres).toSet().toList()..sort();
    final regions = games.expand((g) => g.regions).toSet().toList()..sort();
    final languages = games.expand((g) => g.languages).toSet().toList()..sort();

    if (!context.mounted) return;

    await FilterBottomSheet.show(
      context,
      currentFilters: currentFilters,
      availableGenres: genres,
      availableRegions: regions,
      availableLanguages: languages,
      availableCollections: collections,
      onApply: (newFilters) {
        ref.read(activeFiltersProvider.notifier).state = newFilters;
        ref.read(paginatedGamesProvider.notifier).reset();
        ref.read(paginatedGamesProvider.notifier).setFilters(newFilters);
        ref.read(paginatedGamesProvider.notifier).loadInitial(
          platformId: ref.read(selectedPlatformIdProvider)?.toString(),
          search: ref.read(searchQueryProvider).isEmpty ? null : ref.read(searchQueryProvider),
        );
      },
    );
  }

  @override
  Map<String, bool> get downloadedStates => ref.watch(downloadedGamesCacheProvider);

  @override
  void refreshDownloadState(DirectoryService dirService, Game game) {
    ref.read(downloadedGamesCacheProvider.notifier).refresh();
  }

  @override
  void refreshAllDownloadStates() {
    ref.read(downloadedGamesCacheProvider.notifier).refresh();
  }

  Widget _buildHorizontalShelf({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Game> games,
    required WidgetRef ref,
  }) {
    if (games.isEmpty) return const SizedBox.shrink();

    final cardAspectRatio = ref.watch(cardAspectRatioProvider);
    final showTitle = ref.watch(showTitleProvider);
    final columnCount = ref.watch(columnCountProvider);
    final cardSpacing = ref.watch(cardSpacingProvider);

    // "home has a -1 in row" logic: Use base columnCount for home (which is one less than grid)
    final screenWidth = MediaQuery.of(context).size.width;
    const padding = 24.0;
    final totalSpacing = cardSpacing * (columnCount - 1);
    final cardWidth = (screenWidth - padding - totalSpacing) / columnCount;
    
    final coverHeight = cardWidth / (cardAspectRatio <= 0 ? 0.75 : cardAspectRatio);
    final footerHeight = showTitle ? 60.0 : 32.0;
    final shelfHeight = coverHeight + footerHeight + 10.0; // Extra buffer

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
        ),
        SizedBox(
          height: shelfHeight,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: games.length,
              itemBuilder: (context, index) {
                final game = games[index];
                final coverUrl = ref.read(rommServiceProvider)?.resolveCoverUrl(game);
                
                // Watch states for GameCard
                final downloadedCache = ref.watch(downloadedGamesCacheProvider);
                final downloads = ref.watch(downloadProvider);
                final isActuallyDownloading = downloads.containsKey(game.id);
                final isDownloaded = (downloadedCache[game.id] ?? false) && !isActuallyDownloading;

                return GestureDetector(
                  onTap: () => _handleGameTap(context, ref, game),
                  child: Container(
                    width: cardWidth,
                    margin: const EdgeInsets.only(right: 12),
                    child: GameCard(
                      game: game,
                      coverUrl: coverUrl,
                      isDownloaded: isDownloaded,
                      platformLogoUrl: game.platformSlug != null
                          ? '${ref.read(rommConfigProvider).value?.baseUrl ?? ''}/assets/platforms/${game.platformSlug}.svg'
                          : null,
                      showTitle: showTitle,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final platformsAsync = ref.watch(platformsProvider);
    final selectedPlatformId = ref.watch(selectedPlatformIdProvider);
    final paginatedState = ref.watch(paginatedGamesProvider);
    final cardAspectRatio = ref.watch(cardAspectRatioProvider);
    final columnCount = ref.watch(columnCountProvider);
    
    // "home has a -1 in row" logic: 
    // The main grid now uses the base columnCount (the normal count).
    // The Home shelf logic inside _buildHorizontalShelf remains the same,
    // where it calculates cardWidth based on the same columnCount, 
    // effectively keeping them at the preferred "Home" size while the 
    // grid remains at the "Normal" size.
    final gridColumnCount = columnCount;

    final cardSpacing = ref.watch(cardSpacingProvider);
    final showTitle = ref.watch(showTitleProvider);
    final directoryServiceAsync = ref.watch(directoryServiceProvider);
    final downloadedCache = ref.watch(downloadedGamesCacheProvider);
    final isSyncing = ref.watch(downloadedGamesCacheProvider.notifier).isSyncing;
    final isHomeSelected = ref.watch(isHomeSelectedProvider);

    // Trigger initial load once service becomes available
    ref.listen(rommServiceProvider, (prev, next) {
      if (prev == null && next != null) {
        ref.read(paginatedGamesProvider.notifier).loadInitial(platformId: null);
      }
    });

    // Reload when platform changes
    ref.listen<int?>(selectedPlatformIdProvider, (prev, next) {
      if (prev != next) {
        ref.read(paginatedGamesProvider.notifier).loadInitial(
          platformId: next?.toString(),
        );
      }
    });

    final rommService = ref.watch(rommServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'freegosy_logo.png',
              height: 32,
              width: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: rommService!.isOffline,
                builder: (context, offline, _) {
                  return Text(
                    offline ? "${rommService.config.baseUrl} - Offline Mode" : rommService.config.baseUrl,
                    style: offline ? const TextStyle(color: Colors.orange) : null,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final hasFilters = ref.watch(activeFiltersProvider).hasActiveFilters;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.tune),
                    tooltip: 'Filter',
                    onPressed: () => _openFilterSheet(context, ref),
                  ),
                  if (hasFilters)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.deepPurple,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.shuffle),
            tooltip: 'Random game',
            onPressed: () async {
              final service = ref.read(rommServiceProvider);
              if (service == null) return;
              final game = await service.getRandomGame();
              if (game == null) return;
              if (context.mounted) _handleGameTap(context, ref, game);
            },
          ),
        ],
      ),
      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (KeyEvent event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f5) {
            _refreshIndicatorKey.currentState?.show();
          }
        },
        child: ExcludeSemantics(
          child: Column(
            children: [
              if (isSyncing)
                const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search games...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
                  ),
                  onChanged: (value) {
                    ref.read(searchQueryProvider.notifier).state = value;
                    ref.read(paginatedGamesProvider.notifier).loadInitial(
                      platformId: ref.read(selectedPlatformIdProvider)?.toString(),
                      search: value.isEmpty ? null : value,
                    );
                  },
                ),
              ),
              platformsAsync.when(
                data: (platforms) => PlatformFilterBar(
                  platforms: platforms,
                  selectedPlatformId: selectedPlatformId,
                  isHome: isHomeSelected,
                  onSelected: (platform) {
                    ref.read(isHomeSelectedProvider.notifier).state = false;
                    ref.read(selectedPlatformIdProvider.notifier).state = platform?.id;
                  },
                  onHomeSelected: () {
                    ref.read(isHomeSelectedProvider.notifier).state = true;
                    ref.read(selectedPlatformIdProvider.notifier).state = null;
                  },
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, s) => Text('Error loading platforms: $e'),
              ),
              if (directoryServiceAsync.value?.status.hasError == true)
                Container(
                  color: Colors.red.withValues(alpha: 0.1),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Storage Error',
                              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${directoryServiceAsync.value!.status.message} (${directoryServiceAsync.value!.status.failedPath})',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          ref.invalidate(directoryServiceProvider);
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: paginatedState.isLoading
                    ? buildSkeletonGrid(cardAspectRatio, gridColumnCount, cardSpacing, context, showTitle: showTitle)
                    : (paginatedState.error != null && !paginatedState.error!.contains('Offline Mode'))
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  'Error: ${paginatedState.error}',
                                  style: const TextStyle(color: Colors.red),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    ref.invalidate(rommServiceProvider);
                                    ref.read(paginatedGamesProvider.notifier).loadInitial(
                                      platformId: ref.read(selectedPlatformIdProvider)?.toString(),
                                      search: ref.read(searchQueryProvider),
                                    );
                                  },
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                        key: _refreshIndicatorKey,
                        onRefresh: _refreshLibrary,
                        child: Consumer(
                          builder: (context, ref, _) {
                            final isHome = ref.watch(isHomeSelectedProvider);
                            final recentAsync = ref.watch(recentlyPlayedProvider);
                            final metadataCacheAsync = ref.watch(metadataCacheServiceProvider);
                            final displayGames = paginatedState.games;

                            if (isHome) {
                              return SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: Column(
                                  children: [
                                    // 1. Continue Playing
                                    recentAsync.when(
                                      loading: () => const SizedBox.shrink(),
                                      error: (e, s) => const SizedBox.shrink(),
                                      data: (games) => _buildHorizontalShelf(
                                        context: context,
                                        title: 'Continue Playing',
                                        icon: Icons.play_circle_outline,
                                        games: games,
                                        ref: ref,
                                      ),
                                    ),
                                    // 2. Recently Added
                                    _buildHorizontalShelf(
                                      context: context,
                                      title: 'Recently Added',
                                      icon: Icons.new_releases_outlined,
                                      games: displayGames.take(15).toList(),
                                      ref: ref,
                                    ),
                                    // 3. Installed Games
                                    metadataCacheAsync.when(
                                      loading: () => const SizedBox.shrink(),
                                      error: (e, s) => const SizedBox.shrink(),
                                      data: (cache) {
                                        // Filter games that are in our downloaded cache
                                        final installed = cache.cachedGames
                                            .where((g) => downloadedCache[g.id] == true)
                                            .toList();
                                        
                                        // Sort by name for now
                                        installed.sort((a, b) => a.displayName.compareTo(b.displayName));

                                        return _buildHorizontalShelf(
                                          context: context,
                                          title: 'Installed Games (${installed.length})',
                                          icon: Icons.download_done,
                                          games: installed,
                                          ref: ref,
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 32),
                                  ],
                                ),
                              );
                            }

                            if (displayGames.isEmpty) {
                              return const Center(child: Text('No games found'));
                            }

                            return CustomScrollView(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        'Showing ${displayGames.length} of ${paginatedState.total} games',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.all(12),
                                  sliver: SliverGrid(
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: gridColumnCount,
                                      crossAxisSpacing: cardSpacing,
                                      mainAxisSpacing: cardSpacing,
                                      mainAxisExtent: calculateCardHeight(gridColumnCount, cardSpacing, cardAspectRatio, context, showTitle: showTitle),
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        if (index == displayGames.length) {
                                          return const Center(
                                              child: Padding(
                                            padding: EdgeInsets.all(16),
                                            child: CircularProgressIndicator(),
                                          ));
                                        }
                                        final game = displayGames[index];
                                        final downloads = ref.watch(downloadProvider);
                                        final isActuallyDownloading = downloads.containsKey(game.id);
                                        final isDownloaded = (downloadedCache[game.id] ?? false) && !isActuallyDownloading;
                                        final coverUrl = ref.read(rommServiceProvider)?.resolveCoverUrl(game);
                                        
                                        return GestureDetector(
                                          onTap: () => _handleGameTap(context, ref, game),
                                          child: GameCard(
                                            game: game,
                                            coverUrl: coverUrl,
                                            isDownloaded: isDownloaded,
                                            platformLogoUrl: game.platformSlug != null
                                                ? '${ref.read(rommConfigProvider).value?.baseUrl ?? ''}/assets/platforms/${game.platformSlug}.svg'
                                                : null,
                                            showTitle: showTitle,
                                          ),
                                        );
                                      },
                                      childCount: displayGames.length + (paginatedState.isLoadingMore ? 1 : 0),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
