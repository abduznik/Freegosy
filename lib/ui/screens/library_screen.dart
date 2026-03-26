import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/library_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/romm_provider.dart';
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
  bool _downloadStatesLoaded = false;

  Future<void> _loadDownloadStates(
      DirectoryService dirService, List<Game> games) async {
    if (_downloadStatesLoaded) return;
    final results = await Future.wait(
      games.map((game) async {
        final isDownloaded = await dirService.isRomDownloaded(game);
        return MapEntry(game.id, isDownloaded);
      }),
    );
    if (mounted) {
      setState(() {
        _downloadedStates = Map.fromEntries(results);
        _downloadStatesLoaded = true;
      });
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
    final registry = ref.read(strategyRegistryProvider);
    final strategy = registry?.getStrategyForSlug(game.platformSlug ?? '');

    if (strategy == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'No emulator configured for ${game.platformDisplayName ?? game.platformSlug ?? 'this platform'}')),
      );
      return;
    }

    final dir = await ref.read(directoryServiceProvider.future);
    if (!context.mounted) return;
    if (dir == null) {
      ScaffoldMessenger.of(context).showSnackBar(
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

    if (ref.read(saveSyncServiceProvider) != null) {
      final syncMode = ref.read(retroarchSyncModeProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pushing saves for ${game.name}...'),
          duration: const Duration(seconds: 30),
        ),
      );
      await ref.read(saveSyncServiceProvider)!.pushSaves(game, existingRomPath, syncMode: syncMode);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      try {
        final pulled = await ref.read(saveSyncServiceProvider)!.pullSave(game, existingRomPath);
        if (!context.mounted) return;
        if (pulled) {
          ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Launching ${game.name}...'),
          duration: const Duration(seconds: 3),
        ),
      );
      await strategy.launch(game, existingRomPath);
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
              ScaffoldMessenger.of(context).showSnackBar(
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
        ScaffoldMessenger.of(context).showSnackBar(
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
    final registry = ref.read(strategyRegistryProvider);
    final windowsStrategy =
        registry?.getStrategyForSlug(game.platformSlug ?? '') as WindowsStrategy?;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => WindowsGameConfigDialog(
        game: game,
        currentExePath: windowsStrategy?.getExeOverride(game.id),
        currentSavePath:
            ref.read(saveSyncServiceProvider)?.windowsSaveStrategy.getManualOverride(game.id),
      ),
    );
    if (result == null) return;
    final exe = result['exe'] ?? '';
    final save = result['save'] ?? '';
    if (exe.isNotEmpty) {
      await windowsStrategy?.setExeOverride(game.id, exe);
    }
    if (save.isNotEmpty) {
      await ref.read(saveSyncServiceProvider)?.windowsSaveStrategy.setManualOverride(game.id, save);
    }
    if (!context.mounted) return;
    await _handleLaunch(context, ref, game);
  }

  Future<void> _handleSyncSaves(
      BuildContext context, WidgetRef ref, Game game) async {
    final syncService = ref.read(saveSyncServiceProvider);
    if (syncService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save sync not available')),
      );
      return;
    }
    final dir = ref.read(directoryServiceProvider).asData?.value;
    final romPath = dir != null ? await dir.getRomFilePath(game) : '';
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Syncing saves for ${game.name}...')),
    );
    final syncMode = ref.read(retroarchSyncModeProvider);
    final ok = await syncService.pushSaves(game, romPath, syncMode: syncMode);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
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
    final searchQuery = ref.watch(searchQueryProvider);
    final gamesAsync = ref.watch(allGamesProvider);
    final filteredGames = ref.watch(filteredGamesProvider);
    final cardAspectRatio = ref.watch(cardAspectRatioProvider);
    final columnCount = ref.watch(columnCountProvider);
    final cardSpacing = ref.watch(cardSpacingProvider);
    final showTitle = ref.watch(showTitleProvider);
    final showButtonsOnHover = ref.watch(showButtonsOnHoverProvider);
    final rommConfigAsync = ref.watch(rommConfigProvider);
    final directoryServiceAsync = ref.watch(directoryServiceProvider);

    final appBarTitle = rommConfigAsync.when(
      data: (config) {
        final uri = Uri.tryParse(config.baseUrl);
        final host = uri?.host ?? config.baseUrl;
        final totalGames = gamesAsync.asData?.value.length;
        final gameCountStr = totalGames != null ? ' • $totalGames games' : '';
        return 'Freegosy • $host$gameCountStr';
      },
      loading: () => 'Freegosy',
      error: (e, s) => 'Freegosy',
    );

    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: ExcludeSemantics(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search games...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                onChanged: (value) {
                  ref.read(searchQueryProvider.notifier).state = value;
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
              child: gamesAsync.when(
                loading: () => buildSkeletonGrid(cardAspectRatio, columnCount, cardSpacing, context),
                error: (e, s) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Error loading games: $e',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
                data: (_) {
                  final gamesCount = filteredGames.length;
                  final countDisplayText =
                      (selectedPlatformId == null && searchQuery.isEmpty)
                          ? 'Showing all $gamesCount games'
                          : 'Showing $gamesCount games';

                  final dirService = directoryServiceAsync.asData?.value;
                  if (dirService != null && !_downloadStatesLoaded) {
                    final games = ref.read(allGamesProvider).asData?.value ?? [];
                    _loadDownloadStates(dirService, games);
                  }

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            countDisplayText,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async {
                            setState(() {
                              _downloadStatesLoaded = false;
                              _downloadedStates = {};
                            });
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.remove('cached_games');
                            await prefs.remove('cached_platforms');
                            await prefs.remove('cached_games_time');
                            await prefs.remove('cached_platforms_time');
                            await prefs.remove('cache_size_exceeded');
                            ref.invalidate(allGamesProvider);
                            ref.invalidate(platformsProvider);
                            await ref.read(allGamesProvider.future);
                          },
                          child: filteredGames.isEmpty
                              ? const CustomScrollView(
                                  slivers: [
                                    SliverFillRemaining(
                                      child: Center(child: Text('No games found')),
                                    ),
                                  ],
                                )
                              : GridView.builder(
                                  padding: const EdgeInsets.all(12),
                                  cacheExtent: 800,
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columnCount,
                                    crossAxisSpacing: cardSpacing,
                                    mainAxisSpacing: cardSpacing,
                                    mainAxisExtent: calculateCardHeight(
                                        columnCount, cardSpacing, cardAspectRatio, context),
                                  ),
                                  itemCount: filteredGames.length,
                                  itemBuilder: (context, index) {
                                    final game = filteredGames[index];
                                    final dirService = directoryServiceAsync.asData?.value;
                                    final isWindowsGame = ['windows', 'pc', 'win']
                                        .contains(game.platformSlug?.toLowerCase() ?? '');
                                    final coverUrl = ref.read(rommServiceProvider)?.resolveCoverUrl(game);

                                    if (dirService == null) {
                                      return GestureDetector(
                                        onLongPress: isWindowsGame
                                            ? () => _handleWindowsConfig(context, ref, game)
                                            : null,
                                        child: GameCard(
                                          game: game,
                                          coverUrl: coverUrl,
                                          showTitle: showTitle,
                                          showButtonsOnHover: showButtonsOnHover,
                                          onDownload: () => _startDownload(context, ref, game),
                                          onLaunch: () => _handleLaunch(context, ref, game),
                                          onSyncSaves: () => _handleSyncSaves(context, ref, game),
                                        ),
                                      );
                                    }

                                    return GestureDetector(
                                      onLongPress: isWindowsGame
                                          ? () => _handleWindowsConfig(context, ref, game)
                                          : null,
                                      child: GameCard(
                                        game: game,
                                        coverUrl: coverUrl,
                                        isDownloaded: _downloadedStates[game.id] ?? false,
                                        showTitle: showTitle,
                                        showButtonsOnHover: showButtonsOnHover,
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}