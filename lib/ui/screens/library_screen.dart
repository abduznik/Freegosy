import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/library_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/romm_provider.dart';
import '../../providers/paginated_games_provider.dart';
import '../../core/storage/directory_service.dart';
import '../../core/romm/romm_models.dart';
import '../../core/emulator/strategies/windows_strategy.dart';
import '../../core/emulator/strategies/retroarch_strategy.dart';
import '../widgets/game_card.dart';
import '../widgets/platform_filter_bar.dart';
import '../widgets/windows_game_config_dialog.dart';
import 'library_skeleton.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  Map<String, bool> _downloadedStates = {};
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

  Future<void> _refreshDownloadState(
      DirectoryService dirService, Game game) async {
    final isDownloaded = await dirService.isRomDownloaded(game);
    if (mounted) {
      setState(() {
        _downloadedStates[game.id] = isDownloaded;
      });
    }
  }

  Future<void> _refreshLibrary() async {
    ref.invalidate(platformsProvider);
    ref.read(paginatedGamesProvider.notifier).reset();
    await ref.read(paginatedGamesProvider.notifier).loadInitial(
      platformId: ref.read(selectedPlatformIdProvider)?.toString(),
      search: ref.read(searchQueryProvider).isEmpty ? null : ref.read(searchQueryProvider),
    );
  }

  void _startDownload(BuildContext context, WidgetRef ref, Game game) {
    final service = ref.read(rommServiceProvider);
    if (service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to RomM')),
      );
      return;
    }
    final url = service.getDownloadUrl(game);
    final basicAuth =
        'Basic ${base64Encode(utf8.encode('${service.config.username}:${service.config.password}'))}';
    final headers = <String, String>{'Authorization': basicAuth};
    ref.read(downloadProvider.notifier).startDownload(game, url, headers: headers);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading ${game.name}...')),
    );
    final dirService = ref.read(directoryServiceProvider).asData?.value;
    if (dirService != null) {
      Future.delayed(const Duration(seconds: 2), () {
        _refreshDownloadState(dirService, game);
      });
    }
  }

  Future<void> _handleLaunch(BuildContext context, WidgetRef ref, Game game) async {
    final messenger = ScaffoldMessenger.of(context);

    // Ensure strategy registry preferences are loaded
    final registryReady = await ref.read(strategyRegistryProvider.future);
    if (registryReady == null) return;
    final strategy = registryReady.getStrategyForSlug(game.platformSlug ?? '');

    if (strategy == null) {
      messenger.showSnackBar(
        SnackBar(
            content: Text(
                'No emulator configured for ${game.platformDisplayName ?? game.platformSlug ?? 'this platform'}')),
      );
      return;
    }

    // Wait for save sync service to be ready (FutureProvider chain)
    final syncService = await ref.read(saveSyncServiceProvider.future);

    final dir = await ref.read(directoryServiceProvider.future);
    if (!context.mounted) return;
    if (dir == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Storage service not available')),
      );
      return;
    }

    final existingRomPath = await dir.findExistingRomPath(game);
    final expectedRomPath = await dir.getRomFilePath(game);
    if (!context.mounted) return;

    if (existingRomPath == null) {
      final shouldDownload = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ROM not found'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${game.name} is not downloaded yet.'),
              const SizedBox(height: 8),
              const Text('Expected location:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              SelectableText(
                expectedRomPath,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              const Text(
                'You can also manually place the ROM file there.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              const Text('Would you like to download it now?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Download'),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (shouldDownload == true) {
        _startDownload(context, ref, game);
      }
      return;
    }

    if (syncService != null) {
      final syncMode = ref.read(retroarchSyncModeProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Pushing saves for ${game.name}...'),
          duration: const Duration(seconds: 30),
        ),
      );
      await syncService.pushSaves(game, existingRomPath, syncMode: syncMode);
      if (!context.mounted) return;
      messenger.clearSnackBars();
      try {
        final pulled = await syncService.pullSave(game, existingRomPath);
        if (!context.mounted) return;
        if (pulled) {
          messenger.showSnackBar(
            const SnackBar(
                content: Text('Cloud save restored'),
                duration: Duration(seconds: 2)),
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Save Sync Warning'),
            content: Text(
                '${e.toString().replaceAll('Exception: ', '')}\n\nYou can still play, but your cloud save will not be restored. After playing once, exit the game and sync saves manually.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Play Anyway'),
              ),
            ],
          ),
        );
        if (!context.mounted) return;
        if (shouldContinue != true) return;
      }
    }

    try {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Launching ${game.name}...'),
          duration: const Duration(seconds: 3),
        ),
      );

      // Try to get process handle for auto-sync when game closes
      Process? process = await strategy.launchWithHandle(game, existingRomPath);
      if (process == null) {
        // Fall back to regular launch if no process handle available
        await strategy.launch(game, existingRomPath);
      } else {
        // Start background Future to handle process exit
        unawaited(Future.delayed(Duration.zero, () async {
          try {
            await process.exitCode;
            if (!context.mounted) return;

            messenger.showSnackBar(
              const SnackBar(
                content: Text('Auto-syncing saves...'),
                duration: Duration(seconds: 2),
              ),
            );

            if (syncService != null) {
              final syncMode = ref.read(retroarchSyncModeProvider);
              await syncService.pushSaves(game, existingRomPath, syncMode: syncMode);
            }

            if (!context.mounted) return;
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Saves synced'),
                duration: Duration(seconds: 2),
              ),
            );
          } catch (e) {
            // Silently ignore errors in auto-sync
          }
        }));
      }
    } catch (e) {
      if (!context.mounted) return;

      if (e is MissingRetroArchCoreException) {
        final shouldDownload = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('RetroArch Core Missing'),
            content: Text(
                'The core ${e.coreName} is required for this game but is not installed. Would you like Freegosy to download and install it automatically?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Install'),
              ),
            ],
          ),
        );
        if (shouldDownload == true && context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const Center(child: CircularProgressIndicator()),
          );
          try {
            final raStrategy = strategy as RetroArchStrategy;
            final coresDir = File(e.corePath).parent.path;
            await raStrategy.downloadCore(e.coreName, coresDir, Dio());
            if (context.mounted) {
              Navigator.of(context).pop();
              await _handleLaunch(context, ref, game);
            }
          } catch (err) {
            if (context.mounted) {
              Navigator.of(context).pop();
              messenger.showSnackBar(
                SnackBar(content: Text('Failed to download core: $err')),
              );
            }
          }
        }
        return;
      }

      final isWindows =
          ['windows', 'pc', 'win'].contains(game.platformSlug?.toLowerCase() ?? '');
      final isMissingExe =
          e.toString().contains('No executable') || e.toString().contains('not found');
      if (isWindows && isMissingExe) {
        await _handleWindowsConfig(context, ref, game);
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Launch failed: $e'),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  Future<void> _handleWindowsConfig(
      BuildContext context, WidgetRef ref, Game game) async {
    final registry = ref.read(strategyRegistryProvider).asData?.value;
    final windowsStrategy =
        registry?.getStrategyForSlug(game.platformSlug ?? '') as WindowsStrategy?;
    final syncService = await ref.read(saveSyncServiceProvider.future);
      if (!context.mounted) return;
      final result = await showDialog<Map<String, String>>(
        context: context,
      builder: (ctx) => WindowsGameConfigDialog(
        game: game,
        currentExePath: windowsStrategy?.getExeOverride(game.id),
        currentSavePath:
            syncService?.windowsSaveStrategy.getManualOverride(game.id),
      ),
    );
    if (result == null) return;
    final exe = result['exe'] ?? '';
    final save = result['save'] ?? '';
    if (exe.isNotEmpty) {
      await windowsStrategy?.setExeOverride(game.id, exe);
    }
    if (save.isNotEmpty) {
      await syncService?.windowsSaveStrategy.setManualOverride(game.id, save);
    }
    if (!context.mounted) return;
    await _handleLaunch(context, ref, game);
  }

  Future<void> _handleSyncSaves(
      BuildContext context, WidgetRef ref, Game game) async {
    final messenger = ScaffoldMessenger.of(context);

    final syncService = await ref.read(saveSyncServiceProvider.future);
    if (syncService == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Save sync not available')),
      );
      return;
    }
    final dir = ref.read(directoryServiceProvider).asData?.value;
    final romPath = dir != null ? await dir.getRomFilePath(game) : '';
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Syncing saves for ${game.name}...')),
    );
    final syncMode = ref.read(retroarchSyncModeProvider);
    final ok = await syncService.pushSaves(game, romPath, syncMode: syncMode);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Saves uploaded for ${game.name}'
            : 'No saves found for ${game.name}'),
      ),
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
      appBar: AppBar(title: Text(appBarTitle)),
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
                    ? Center(child: Padding(
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
                              child: paginatedState.games.isEmpty
                                ? const CustomScrollView(slivers: [
                                    SliverFillRemaining(child: Center(child: Text('No games found'))),
                                  ])
                                : GridView.builder(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.all(12),
                                    cacheExtent: 800,
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columnCount,
                                      crossAxisSpacing: cardSpacing,
                                      mainAxisSpacing: cardSpacing,
                                      mainAxisExtent: calculateCardHeight(columnCount, cardSpacing, cardAspectRatio, context),
                                    ),
                                    itemCount: paginatedState.games.length + (paginatedState.isLoadingMore ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index == paginatedState.games.length) {
                                        return const Center(child: Padding(
                                          padding: EdgeInsets.all(16),
                                          child: CircularProgressIndicator(),
                                        ));
                                      }
                                      final game = paginatedState.games[index];
                                      final dirService = directoryServiceAsync.asData?.value;
                                      final isWindowsGame = ['windows', 'pc', 'win'].contains(game.platformSlug?.toLowerCase() ?? '');
                                      final coverUrl = ref.read(rommServiceProvider)?.resolveCoverUrl(game);
                                      if (dirService == null) {
                                        return GestureDetector(
                                          onLongPress: isWindowsGame ? () => _handleWindowsConfig(context, ref, game) : null,
                                          child: GameCard(
                                            game: game, coverUrl: coverUrl, showTitle: showTitle,
                                            showButtonsOnHover: showButtonsOnHover,
                                            onDownload: () => _startDownload(context, ref, game),
                                            onLaunch: () => _handleLaunch(context, ref, game),
                                            onSyncSaves: () => _handleSyncSaves(context, ref, game),
                                          ),
                                        );
                                      }
                                      return GestureDetector(
                                        onLongPress: isWindowsGame ? () => _handleWindowsConfig(context, ref, game) : null,
                                        child: GameCard(
                                          game: game, coverUrl: coverUrl,
                                          isDownloaded: _downloadedStates[game.id] ?? false,
                                          showTitle: showTitle, showButtonsOnHover: showButtonsOnHover,
                                          onDownload: () => _startDownload(context, ref, game),
                                          onLaunch: () => _handleLaunch(context, ref, game),
                                          onSyncSaves: () => _handleSyncSaves(context, ref, game),
                                        ),
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