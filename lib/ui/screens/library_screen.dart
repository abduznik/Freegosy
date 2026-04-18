import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
    final isDownloaded = ref.read(downloadedGamesCacheProvider)[game.id] ?? false;

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

  @override
  Widget build(BuildContext context) {
    final platformsAsync = ref.watch(platformsProvider);
    final selectedPlatformId = ref.watch(selectedPlatformIdProvider);
    final paginatedState = ref.watch(paginatedGamesProvider);
    final cardAspectRatio = ref.watch(cardAspectRatioProvider);
    final columnCount = ref.watch(columnCountProvider);
    final cardSpacing = ref.watch(cardSpacingProvider);
    final showTitle = ref.watch(showTitleProvider);
    final showButtonsOnHover = ref.watch(showButtonsOnHoverProvider);
    final rommConfigAsync = ref.watch(rommConfigProvider);
    final directoryServiceAsync = ref.watch(directoryServiceProvider);
    final downloadedCache = ref.watch(downloadedGamesCacheProvider);
    final isSyncing = ref.watch(downloadedGamesCacheProvider.notifier).isSyncing;
    final activeFilters = ref.watch(activeFiltersProvider);

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

    final appBarTitle = rommConfigAsync.when(
      data: (config) {
        final uri = Uri.tryParse(config.baseUrl);
        final host = uri?.host ?? config.baseUrl;
        final gameCountStr = ' • ${paginatedState.total} games';
        return 'Freegosy • $host$gameCountStr';
      },
      loading: () => 'Freegosy',
      error: (e, s) => 'Freegosy',
    );

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
            Expanded(child: Text(appBarTitle, overflow: TextOverflow.ellipsis)),
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
          // Random game button
          Consumer(
            builder: (context, ref, _) {
              return IconButton(
                icon: const Icon(Icons.shuffle),
                tooltip: 'Random game',
                onPressed: () async {
                  final service = ref.read(rommServiceProvider);
                  if (service == null) return;
                  final game = await service.getRandomGame();
                  if (game == null) return;
                  if (context.mounted) _handleGameTap(context, ref, game);
                },
              );
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
                  downloadedOnly: activeFilters.downloadedOnly,
                  onSelected: (platform) {
                    ref.read(selectedPlatformIdProvider.notifier).state = platform?.id;
                  },
                  onDownloadedToggle: (selected) {
                    final notifier = ref.read(activeFiltersProvider.notifier);
                    notifier.state = notifier.state.copyWith(downloadedOnly: selected);
                    // Refresh games list with new filter
                    ref.read(paginatedGamesProvider.notifier).loadInitial(
                      platformId: selectedPlatformId?.toString(),
                      search: _searchController.text.isEmpty ? null : _searchController.text,
                    );
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
                          // Navigate to settings (it's the 3rd tab, index 2)
                          // Assuming we can find the parent Scaffold or similar
                          // For now, let's just use a simple Navigator.push to SettingsScreen if possible, 
                          // but the app uses a bottom bar.
                          // Let's just provide a Retry for now as it's more direct.
                          ref.invalidate(directoryServiceProvider);
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              if (paginatedState.error != null && paginatedState.error!.contains('Offline Mode'))
                Container(
                  color: Colors.orange.withValues(alpha: 0.1),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Offline Mode',
                              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              paginatedState.error!,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
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
                ),
              Expanded(
                child: paginatedState.isLoading
                    ? buildSkeletonGrid(cardAspectRatio, columnCount, cardSpacing, context)
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
                        : Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    selectedPlatformId == null
                                        ? 'Showing ${paginatedState.games.length} of ${paginatedState.total} games'
                                        : 'Showing ${paginatedState.games.length} of ${paginatedState.total} games',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: RefreshIndicator(
                                  key: _refreshIndicatorKey,
                                  onRefresh: _refreshLibrary,
                                  child: Consumer(
                                    builder: (context, ref, _) {
                                      final activeFilters = ref.watch(activeFiltersProvider);
                                      final selectedPlatform = ref.watch(selectedPlatformIdProvider);
                                      final search = ref.watch(searchQueryProvider);
                                      final hasFilters = activeFilters.hasActiveFilters ||
                                          selectedPlatform != null ||
                                          search.isNotEmpty;

                                      final recentAsync = ref.watch(recentlyPlayedProvider);

                                      final displayGames = paginatedState.games;

                                      if (paginatedState.games.isEmpty) {
                                        return const CustomScrollView(slivers: [
                                          SliverFillRemaining(child: Center(child: Text('No games found'))),
                                        ]);
                                      }

                                      if (displayGames.isEmpty) {
                                        return const CustomScrollView(slivers: [
                                          SliverFillRemaining(child: Center(child: Text('No games match your filters'))),
                                        ]);
                                      }

                                      return CustomScrollView(
                                        controller: _scrollController,
                                        physics: const AlwaysScrollableScrollPhysics(),
                                        slivers: [
                                          if (!hasFilters)
                                            SliverToBoxAdapter(
                                              child: recentAsync.when(
                                                loading: () => const SizedBox.shrink(),
                                                error: (e, s) => const SizedBox.shrink(),
                                                data: (games) {
                                                  if (games.isEmpty) return const SizedBox.shrink();
                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Padding(
                                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                        child: Row(
                                                          children: [
                                                            const Icon(Icons.play_circle_outline, size: 18),
                                                            const SizedBox(width: 6),
                                                            const Text('Continue Playing',
                                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                          ],
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        height: 160,
                                                        child: ListView.builder(
                                                          scrollDirection: Axis.horizontal,
                                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                                          itemCount: games.length,
                                                          itemBuilder: (context, index) {
                                                            final game = games[index];
                                                            final coverUrl = ref.read(rommServiceProvider)?.resolveCoverUrl(game);
                                                            return GestureDetector(
                                                              onTap: () => _handleGameTap(context, ref, game),
                                                              child: Container(
                                                                width: 100,
                                                                margin: const EdgeInsets.only(right: 8),
                                                                child: Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    Expanded(
                                                                      child: ClipRRect(
                                                                        borderRadius: BorderRadius.circular(8),
                                                                        child: coverUrl != null
                                                                            ? CachedNetworkImage(
                                                                                imageUrl: coverUrl,
                                                                                fit: BoxFit.cover,
                                                                                width: 100,
                                                                                errorWidget: (c, u, e) => Container(
                                                                                  color: Colors.grey[800],
                                                                                  child: const Icon(Icons.sports_esports),
                                                                                ),
                                                                              )
                                                                            : Container(
                                                                                color: Colors.grey[800],
                                                                                child: const Icon(Icons.sports_esports),
                                                                              ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(height: 4),
                                                                    Text(
                                                                      game.displayName,
                                                                      maxLines: 1,
                                                                      overflow: TextOverflow.ellipsis,
                                                                      style: const TextStyle(fontSize: 11),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                          SliverPadding(
                                            padding: const EdgeInsets.all(12),
                                            sliver: SliverGrid(
                                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: columnCount,
                                                crossAxisSpacing: cardSpacing,
                                                mainAxisSpacing: cardSpacing,
                                                mainAxisExtent: calculateCardHeight(columnCount, cardSpacing, cardAspectRatio, context),
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
                                                  final isDownloaded = downloadedCache[game.id] ?? false;
                                                  final isWindowsGame = ['windows', 'pc', 'win'].contains(game.platformSlug?.toLowerCase() ?? '');
                                                  final coverUrl = ref.read(rommServiceProvider)?.resolveCoverUrl(game);
                                                  
                                                  return GestureDetector(
                                                    onTap: () => _handleGameTap(context, ref, game),
                                                    child: GestureDetector(
                                                      onLongPress: isWindowsGame ? () => handleWindowsConfig(context, ref, game) : null,
                                                      child: GameCard(
                                                        game: game,
                                                        coverUrl: coverUrl,
                                                        isDownloaded: isDownloaded,
                                                        platformLogoUrl: game.platformSlug != null
                                                            ? '${ref.read(rommConfigProvider).value?.baseUrl ?? ''}/assets/platforms/${game.platformSlug}.svg'
                                                            : null,
                                                        showTitle: showTitle,
                                                        showButtonsOnHover: showButtonsOnHover,
                                                        onDownload: () => startDownload(context, ref, game),
                                                        onLaunch: () => handleLaunch(context, ref, game),
                                                        onDelete: () => handleDeleteRom(context, ref, game),
                                                        onPushSaves: () => handlePushSaves(context, ref, game),
                                                        onPullSaves: () => handlePullSaves(context, ref, game),
                                                      ),
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
            ],
          ),
        ),
      ),
    );
  }
}
