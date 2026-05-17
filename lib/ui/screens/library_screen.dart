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
import '../../core/input/input_action_bus.dart';
import '../../core/input/gamepad_service.dart';

import '../../providers/download_provider.dart';
import '../../providers/ui_provider.dart';
import '../widgets/focus_effect_wrapper.dart';
import '../widgets/controller_hints_bar.dart';

final isHomeSelectedProvider = StateProvider<bool>((ref) => true);

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with LibraryActionsMixin {
  late TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _platformTabsFocusNode = FocusNode();
  final FocusNode _firstPlatformChipFocusNode = FocusNode();
  final FocusNode _topActionsFocusNode = FocusNode();
  final FocusNode _firstContentItemFocusNode = FocusNode();
  
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  late ScrollController _scrollController;
  StreamSubscription<GameAction>? _inputSub;
  bool _isFilterSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: ref.read(searchQueryProvider));
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    _inputSub = inputActionBus.stream.listen((action) {
      if (!mounted) return;
      switch (action) {
        case GameAction.detail:
          if (_isFilterSheetOpen) Navigator.pop(context);
          else _openFilterSheet(context, ref);
          break;
        case GameAction.favorite:
          _scrollToTopAndFocusSearch();
          break;
        default:
          break;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToTopAndFocusSearch();
    });
  }

  void _scrollToTopAndFocusSearch() {
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
    _searchFocusNode.requestFocus();
  }

  Future<void> _handleRandomGame() async {
    final service = ref.read(rommServiceProvider);
    if (service == null) return;
    final game = await service.getRandomGame();
    if (game == null) return;
    if (mounted) _handleGameTap(context, ref, game);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _platformTabsFocusNode.dispose();
    _firstPlatformChipFocusNode.dispose();
    _topActionsFocusNode.dispose();
    _firstContentItemFocusNode.dispose();
    _scrollController.dispose();
    _inputSub?.cancel();
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
    ref.invalidate(recentlyAddedProvider);
    ref.invalidate(recentlyPlayedProvider);
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
    if (mounted) await ref.read(downloadedGamesCacheProvider.notifier).refresh();
  }

  Future<void> _openFilterSheet(BuildContext context, WidgetRef ref) async {
    final currentFilters = ref.read(activeFiltersProvider);
    final collections = await ref.read(rommServiceProvider)?.getCollections() ?? [];
    final games = ref.read(paginatedGamesProvider).games;
    final genres = games.expand((g) => g.genres).toSet().toList()..sort();
    final regions = games.expand((g) => g.regions).toSet().toList()..sort();
    final languages = games.expand((g) => g.languages).toSet().toList()..sort();

    if (!context.mounted) return;
    setState(() => _isFilterSheetOpen = true);
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
    if (mounted) setState(() => _isFilterSheetOpen = false);
  }

  @override
  Map<String, bool> get downloadedStates => ref.watch(downloadedGamesCacheProvider);
  @override
  void refreshDownloadState(DirectoryService dirService, Game game) => ref.read(downloadedGamesCacheProvider.notifier).refresh();
  @override
  void refreshAllDownloadStates() => ref.read(downloadedGamesCacheProvider.notifier).refresh();

  Widget _buildHorizontalShelf({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Game> games,
    required WidgetRef ref,
    bool isFirst = false,
  }) {
    if (games.isEmpty) return const SizedBox.shrink();
    final cardAspectRatio = ref.watch(cardAspectRatioProvider);
    final showTitle = ref.watch(showTitleProvider);
    final columnCount = ref.watch(columnCountProvider);
    final cardSpacing = ref.watch(cardSpacingProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    const padding = 24.0;
    final totalSpacing = cardSpacing * (columnCount - 1);
    final cardWidth = (screenWidth - padding - totalSpacing) / columnCount;
    final coverHeight = cardWidth / (cardAspectRatio <= 0 ? 0.75 : cardAspectRatio);
    final footerHeight = showTitle ? 60.0 : 32.0;
    final shelfHeight = coverHeight + footerHeight + 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
        ),
        SizedBox(
          height: shelfHeight,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: games.length,
              itemBuilder: (context, index) {
                final game = games[index];
                final coverUrl = ref.read(rommServiceProvider)?.resolveCoverUrl(game);
                final downloadedCache = ref.watch(downloadedGamesCacheProvider);
                final downloads = ref.watch(downloadProvider);
                final isActuallyDownloading = downloads.containsKey(game.id);
                final isDownloaded = (downloadedCache[game.id] ?? false) && !isActuallyDownloading;

                return Container(
                  width: cardWidth,
                  margin: const EdgeInsets.only(right: 12),
                  child: FocusEffectWrapper(
                    focusNode: (isFirst && index == 0) ? _firstContentItemFocusNode : null,
                    onTap: () => _handleGameTap(context, ref, game),
                    child: GameCard(
                      game: game,
                      coverUrl: coverUrl,
                      isDownloaded: isDownloaded,
                      platformLogoUrl: game.platformSlug != null ? '${ref.read(rommConfigProvider).value?.baseUrl ?? ''}/assets/platforms/${game.platformSlug}.svg' : null,
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
    final gridColumnCount = columnCount;
    final cardSpacing = ref.watch(cardSpacingProvider);
    final showTitle = ref.watch(showTitleProvider);
    final directoryServiceAsync = ref.watch(directoryServiceProvider);
    final downloadedCache = ref.watch(downloadedGamesCacheProvider);
    final isSyncing = ref.watch(downloadedGamesCacheProvider.notifier).isSyncing;
    final isHomeSelected = ref.watch(isHomeSelectedProvider);
    final rommService = ref.watch(rommServiceProvider);
    final inputMode = ref.watch(inputModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('freegosy_logo.png', height: 32, width: 32),
            const SizedBox(width: 12),
            Expanded(
              child: rommService == null 
                ? Consumer(builder: (context, ref, _) => Text(ref.watch(rommConfigProvider).value?.baseUrl ?? 'Loading...', style: const TextStyle(color: Colors.grey), overflow: TextOverflow.ellipsis))
                : ValueListenableBuilder<bool>(
                    valueListenable: rommService.isOffline,
                    builder: (context, offline, _) => Text(
                      offline ? "${rommService.config.baseUrl} - Offline Mode" : rommService.config.baseUrl,
                      style: offline ? const TextStyle(color: Colors.orange) : null,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            ),
          ],
        ),
        actions: [
          Focus(
            focusNode: _topActionsFocusNode,
            skipTraversal: true,
            onKeyEvent: (node, event) {
              if (event is! KeyUpEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _scrollToTopAndFocusSearch();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final hasFilters = ref.watch(activeFiltersProvider).hasActiveFilters;
                    final isScanning = ref.watch(isScanningProvider);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isScanning) const Padding(padding: EdgeInsets.only(right: 4.0), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                        FocusEffectWrapper(
                          borderRadius: 24, scaleFactor: 1.1,
                          onTap: () => _openFilterSheet(context, ref),
                          child: Stack(
                            children: [
                              IconButton(icon: const Icon(Icons.tune), tooltip: 'Filter', onPressed: () => _openFilterSheet(context, ref)),
                              if (hasFilters) Positioned(right: 8, top: 8, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.deepPurple, shape: BoxShape.circle))),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                FocusEffectWrapper(borderRadius: 24, scaleFactor: 1.1, onTap: _handleRandomGame, child: IconButton(icon: const Icon(Icons.shuffle), tooltip: 'Random game', onPressed: _handleRandomGame)),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
      body: Listener(
        onPointerHover: (event) {
          if (event.delta.distance > 0 && ref.read(inputModeProvider) != InputMode.mouse) ref.read(inputModeProvider.notifier).state = InputMode.mouse;
        },
        child: Column(
          children: [
            if (isSyncing) const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
            Expanded(
              child: RefreshIndicator(
                key: _refreshIndicatorKey,
                onRefresh: _refreshLibrary,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      sliver: SliverToBoxAdapter(
                        child: Focus(
                          focusNode: _searchFocusNode,
                          onKeyEvent: (node, event) {
                            if (event is! KeyUpEvent) {
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                _firstPlatformChipFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                _topActionsFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search games...', 
                              prefixIcon: const Icon(Icons.search), 
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
                              // Exclusive Focus Visuals:
                              // Only show the focused border color if we are NOT in mouse mode
                              enabledBorder: (inputMode == InputMode.mouse) 
                                ? null 
                                : OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                                  ),
                            ),
                            onChanged: (value) {
                              ref.read(searchQueryProvider.notifier).state = value;
                              ref.read(paginatedGamesProvider.notifier).loadInitial(platformId: ref.read(selectedPlatformIdProvider)?.toString(), search: value.isEmpty ? null : value);
                            },
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: platformsAsync.when(
                        data: (platforms) => PlatformFilterBar(
                          platforms: platforms,
                          selectedPlatformId: selectedPlatformId,
                          isHome: isHomeSelected,
                          focusNode: _platformTabsFocusNode,
                          firstChipFocusNode: _firstPlatformChipFocusNode,
                          onNavigateUp: () => _scrollToTopAndFocusSearch(),
                          onNavigateDown: () {
                            _firstContentItemFocusNode.requestFocus();
                          },
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
                    ),
                    if (directoryServiceAsync.value?.status.hasError == true)
                      SliverToBoxAdapter(
                        child: Container(
                          color: Colors.red.withValues(alpha: 0.1), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(children: [const Icon(Icons.error_outline, color: Colors.red), const SizedBox(width: 12), Expanded(child: Text('${directoryServiceAsync.value!.status.message}', style: const TextStyle(color: Colors.white70, fontSize: 12))), TextButton(onPressed: () => ref.invalidate(directoryServiceProvider), child: const Text('Retry'))]),
                        ),
                      ),
                    if (rommService == null)
                      const SliverFillRemaining(child: Center(child: Text('Setup Required in Settings')))
                    else if (paginatedState.isLoading)
                      buildSkeletonSliverGrid(cardAspectRatio, gridColumnCount, cardSpacing, context, showTitle: showTitle)
                    else if (paginatedState.error != null)
                      SliverFillRemaining(child: Center(child: Text('Error: ${paginatedState.error}')))
                    else
                      Consumer(
                        builder: (context, ref, _) {
                          final isHome = ref.watch(isHomeSelectedProvider);
                          final displayGames = paginatedState.games;
                          if (isHome) {
                            return SliverList(
                              delegate: SliverChildListDelegate([
                                ref.watch(recentlyPlayedProvider).when(data: (games) => _buildHorizontalShelf(context: context, title: 'Continue Playing', icon: Icons.play_circle_outline, games: games, ref: ref, isFirst: true), error: (e, s) => const SizedBox.shrink(), loading: () => const SizedBox.shrink()),
                                ref.watch(recentlyAddedProvider).when(data: (games) => _buildHorizontalShelf(context: context, title: 'Recently Added', icon: Icons.new_releases_outlined, games: games, ref: ref), error: (e, s) => const SizedBox.shrink(), loading: () => const SizedBox.shrink()),
                                ref.watch(metadataCacheServiceProvider).when(data: (cache) {
                                    final installed = cache.cachedGames.where((g) => downloadedCache[g.id] == true).toList()..sort((a, b) => a.displayName.compareTo(b.displayName));
                                    return _buildHorizontalShelf(context: context, title: 'Installed Games (${installed.length})', icon: Icons.download_done, games: installed, ref: ref);
                                }, error: (e, s) => const SizedBox.shrink(), loading: () => const SizedBox.shrink()),
                                const SizedBox(height: 32),
                              ]),
                            );
                          }
                          if (displayGames.isEmpty) return const SliverFillRemaining(child: Center(child: Text('No games found')));
                          return SliverMainAxisGroup(
                            slivers: [
                              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('Showing ${displayGames.length} of ${paginatedState.total} games', style: const TextStyle(fontSize: 12, color: Colors.grey)))),
                              SliverPadding(
                                padding: const EdgeInsets.all(12),
                                sliver: SliverGrid(
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: gridColumnCount, crossAxisSpacing: cardSpacing, mainAxisSpacing: cardSpacing, mainAxisExtent: calculateCardHeight(gridColumnCount, cardSpacing, cardAspectRatio, context, showTitle: showTitle)),
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      if (index == displayGames.length) return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                                      final game = displayGames[index];
                                      final coverUrl = ref.read(rommServiceProvider)?.resolveCoverUrl(game);
                                      final isDownloaded = (downloadedCache[game.id] ?? false) && !ref.watch(downloadProvider).containsKey(game.id);
                                      return FocusEffectWrapper(
                                        focusNode: index == 0 ? _firstContentItemFocusNode : null,
                                        onTap: () => _handleGameTap(context, ref, game),
                                        child: GameCard(game: game, coverUrl: coverUrl, isDownloaded: isDownloaded, platformLogoUrl: game.platformSlug != null ? '${ref.read(rommConfigProvider).value?.baseUrl ?? ''}/assets/platforms/${game.platformSlug}.svg' : null, showTitle: showTitle),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) => SlideTransition(position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)), child: child),
        child: ref.watch(inputModeProvider) != InputMode.mouse
            ? const ControllerHintsBar(hints: [ControllerHintItem(label: 'Select', button: 'A'), ControllerHintItem(label: 'Filter', button: 'X'), ControllerHintItem(label: 'Search', button: 'Y')])
            : const SizedBox.shrink(key: ValueKey('hide_hints')),
      ),
    );
  }
}
