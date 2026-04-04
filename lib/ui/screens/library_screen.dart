import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/library_provider.dart';
import '../../providers/romm_provider.dart';
import '../../providers/paginated_games_provider.dart';
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
  final Map<String, bool> _downloadedStates = {};
  Set<String> _allDownloadedFileNames = {};
  List<Game> _downloadedGames = [];
  bool _isLoadingDownloaded = false;
  late TextEditingController _searchController;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  late ScrollController _scrollController;

  @override
  Map<String, bool> get downloadedStates => _downloadedStates;

  @override
  void refreshDownloadState(DirectoryService dirService, Game game) {
    _refreshDownloadState(dirService, game);
  }

  @override
  void refreshAllDownloadStates() {
    _refreshAllDownloadStates();
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: ref.read(searchQueryProvider));
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _loadAllDownloadedFileNames().then((names) {
        // Load persisted cache first for instant availability
        final cache = ref.read(downloadCacheServiceProvider);
        cache.load().then((_) {
          // Then rescan filesystem and update cache
          if (_allDownloadedFileNames.isNotEmpty) {
            final dirService = ref.read(directoryServiceProvider).asData?.value;
            if (dirService != null) {
              dirService.getAllDownloadedFileNamesByPlatform().then((platformMap) {
                cache.rescanFromPlatformMap(platformMap);
                _refreshAllDownloadStates();
              });
            } else {
              cache.rescanFromDirectory(_allDownloadedFileNames);
              _refreshAllDownloadStates();
            }
          } else {
            _refreshAllDownloadStates();
          }
        });
      });
    });
  }

  Future<void> _loadAllDownloadedFileNames() async {
    final dirService = ref.read(directoryServiceProvider).asData?.value;
    if (dirService == null) return;
    final platformMap = await dirService.getAllDownloadedFileNamesByPlatform();
    final cache = ref.read(downloadCacheServiceProvider);
    cache.rescanFromPlatformMap(platformMap);
    // Also keep _allDownloadedFileNames for backward compat
    final allNames = platformMap.values.expand((s) => s).toSet();
    if (mounted) {
      setState(() {
        _allDownloadedFileNames = allNames;
      });
    }
  }

  Future<void> _loadDownloadedGames() async {
    if (mounted) setState(() => _isLoadingDownloaded = true);
    
    // Always rescan filesystem first to get fresh data
    await _loadAllDownloadedFileNames();
    
    final cache = ref.read(downloadCacheServiceProvider);
    final service = ref.read(rommServiceProvider);
    if (service == null) {
      if (mounted) setState(() => _isLoadingDownloaded = false);
      return;
    }

    final platformMap = cache.filesByPlatform;
    if (platformMap.isEmpty) {
      if (mounted) setState(() => _isLoadingDownloaded = false);
      return;
    }

    final platforms = ref.read(platformsProvider).value ?? [];
    final List<Game> allDownloaded = [];

    for (final entry in platformMap.entries) {
      final slug = entry.key;
      if (slug.isEmpty) continue;

      final platform = platforms.firstWhere(
        (p) => p.slug == slug || p.fsSlug == slug,
        orElse: () => platforms.firstWhere(
          (p) => p.slug.contains(slug) || slug.contains(p.slug),
          orElse: () => Platform(id: -1, name: '', slug: '', fsSlug: '', displayName: ''),
        ),
      );
      if (platform.id == -1) continue;

      try {
        int offset = 0;
        const pageSize = 50;
        while (true) {
          final result = await service.getGamesPage(
            offset: offset,
            limit: pageSize,
            platformId: platform.id.toString(),
          );
          final downloaded = result.games.where((g) =>
            cache.isDownloaded(g.fsName) || cache.isDownloaded(g.fileName)
          ).toList();
          allDownloaded.addAll(downloaded);
          if (offset + pageSize >= result.total) break;
          offset += pageSize;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _downloadedGames = allDownloaded;
        _isLoadingDownloaded = false;
        for (final game in allDownloaded) {
          _downloadedStates[game.id] = true;
        }
      });
    }
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

  Future<void> _refreshDownloadState(
      DirectoryService dirService, Game game) async {
    final isDownloaded = await dirService.isRomDownloaded(game);
    if (mounted) {
      setState(() {
        _downloadedStates[game.id] = isDownloaded;
      });
      if (ref.read(activeFiltersProvider).downloadedOnly) {
        _loadDownloadedGames();
      }
    }
  }

  Future<void> _refreshLibrary() async {
    ref.invalidate(platformsProvider);
    ref.read(paginatedGamesProvider.notifier).reset();
    await ref.read(paginatedGamesProvider.notifier).loadInitial(
      platformId: ref.read(selectedPlatformIdProvider)?.toString(),
      search: ref.read(searchQueryProvider).isEmpty ? null : ref.read(searchQueryProvider),
    );
    await _refreshAllDownloadStates();
    await _loadAllDownloadedFileNames();
  }

  Future<void> _refreshAllDownloadStates() async {
    final dirService = ref.read(directoryServiceProvider).asData?.value;
    if (dirService == null) return;
    
    final games = ref.read(paginatedGamesProvider).games;
    final recentGames = ref.read(recentlyPlayedProvider).value ?? [];
    final allGames = {...games, ...recentGames}.toList();
    
    if (allGames.isEmpty) return;
    
    final results = await Future.wait(
      allGames.map((g) async => MapEntry(g.id, await dirService.isRomDownloaded(g))),
    );
    if (mounted) {
      setState(() {
        for (final entry in results) {
          _downloadedStates[entry.key] = entry.value;
        }
      });
    }
  }

  void _handleGameTap(BuildContext context, WidgetRef ref, Game game) {
    final config = ref.read(rommConfigProvider).value;
    final baseUrl = config?.baseUrl ?? '';
    final isDownloaded = _downloadedStates[game.id] ?? false;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameDetailScreen(
          game: game,
          rommBaseUrl: baseUrl,
          isDownloaded: isDownloaded,
          rommService: ref.read(rommServiceProvider),
          onLaunch: isDownloaded ? () => handleLaunch(context, ref, game) : () {},
          onDownload: () => startDownload(context, ref, game),
          onPushSaves: isDownloaded ? () => handlePushSaves(context, ref, game) : () {},
          onPullSaves: isDownloaded ? () => handlePullSaves(context, ref, game) : () {},
          onDelete: () => handleDeleteRom(context, ref, game),
        ),
      ),
    );
  }

  Future<void> _openFilterSheet(BuildContext context, WidgetRef ref) async {
    // Get available filter values from the platforms filter_values
    // Use the filter_values we already have from the last API response
    final currentFilters = ref.read(activeFiltersProvider);
    final collections = await ref.read(rommServiceProvider)?.getCollections() ?? [];

    // Extract available genres/regions/languages from currently loaded games
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
      downloadedStates: _downloadedStates,
      onApply: (newFilters) {
        ref.read(activeFiltersProvider.notifier).state = newFilters;
        ref.read(paginatedGamesProvider.notifier).reset();
        ref.read(paginatedGamesProvider.notifier).setFilters(newFilters);
        ref.read(paginatedGamesProvider.notifier).loadInitial(
          platformId: ref.read(selectedPlatformIdProvider)?.toString(),
          search: ref.read(searchQueryProvider).isEmpty ? null : ref.read(searchQueryProvider),
        );
        if (newFilters.downloadedOnly) {
          _loadDownloadedGames();
        }
      },
    );
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
        title: Text(appBarTitle),
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
                  onSelected: (platform) {
                    ref.read(selectedPlatformIdProvider.notifier).state = platform?.id;
                  },
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, s) => Text('Error loading platforms: $e'),
              ),
              Expanded(
                child: paginatedState.isLoading
                    ? buildSkeletonGrid(cardAspectRatio, columnCount, cardSpacing, context)
                    : paginatedState.error != null
                        ? Center(
                            child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Error: ${paginatedState.error}', style: const TextStyle(color: Colors.red)),
                          ))
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

                                      final downloadCache = ref.read(downloadCacheServiceProvider);
                                      final displayGames = activeFilters.downloadedOnly
                                          ? _downloadedGames
                                          : activeFilters.notDownloadedOnly
                                              ? paginatedState.games.where((game) {
                                                  final isDownloaded = downloadCache.isDownloaded(game.fsName) ||
                                                      downloadCache.isDownloaded(game.fileName) ||
                                                      _downloadedStates[game.id] == true;
                                                  return !isDownloaded;
                                                }).toList()
                                              : paginatedState.games;

                                      if (activeFilters.downloadedOnly && _isLoadingDownloaded) {
                                        return const Center(child: CircularProgressIndicator());
                                      }

                                      if (paginatedState.games.isEmpty && !activeFilters.downloadedOnly) {
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
                                                  // Refresh download states for recently played games
                                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                                    if (mounted) _refreshAllDownloadStates();
                                                  });

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

                                                  if (_downloadedStates[game.id] == null) {
                                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                                      _refreshAllDownloadStates();
                                                    });
                                                  }
                                                  final dirService = directoryServiceAsync.asData?.value;
                                                  final isWindowsGame = ['windows', 'pc', 'win'].contains(game.platformSlug?.toLowerCase() ?? '');
                                                  final coverUrl = ref.read(rommServiceProvider)?.resolveCoverUrl(game);
                                                  if (dirService == null) {
                                                    return GestureDetector(
                                                      onTap: () => _handleGameTap(context, ref, game),
                                                      child: GestureDetector(
                                                        onLongPress: isWindowsGame ? () => handleWindowsConfig(context, ref, game) : null,
                                                        child: GameCard(
                                                          game: game,
                                                          coverUrl: coverUrl,
                                                          showTitle: showTitle,
                                                          platformLogoUrl: game.platformSlug != null
                                                              ? '${ref.read(rommConfigProvider).value?.baseUrl ?? ''}/assets/platforms/${game.platformSlug}.svg'
                                                              : null,
                                                          showButtonsOnHover: showButtonsOnHover,
                                                          onDownload: () => startDownload(context, ref, game),
                                                          onLaunch: () => handleLaunch(context, ref, game),
                                                          onDelete: () => handleDeleteRom(context, ref, game),
                                                          onPushSaves: () => handlePushSaves(context, ref, game),
                                                          onPullSaves: () => handlePullSaves(context, ref, game),
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  return GestureDetector(
                                                    onTap: () => _handleGameTap(context, ref, game),
                                                    child: GestureDetector(
                                                      onLongPress: isWindowsGame ? () => handleWindowsConfig(context, ref, game) : null,
                                                      child: GameCard(
                                                        game: game,
                                                        coverUrl: coverUrl,
                                                        isDownloaded: _downloadedStates[game.id] ?? false,
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
