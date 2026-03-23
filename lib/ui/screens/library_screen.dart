import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/library_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/romm_provider.dart';
import '../../core/romm/romm_models.dart';
import '../widgets/game_card.dart';
import '../widgets/platform_filter_bar.dart';
import 'dart:convert';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  Future<void> _handleLaunch(BuildContext context, WidgetRef ref, game) async {
    final registry = ref.read(strategyRegistryProvider);
    final strategy = registry?.getStrategyForSlug(game.platformSlug ?? '');

    if (strategy == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No emulator configured for ${game.platformDisplayName ?? game.platformSlug ?? 'this platform'}')),
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
              const Text('Expected location:', style: TextStyle(fontWeight: FontWeight.bold)),
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

    // Pull latest cloud save before launching
    final syncService = ref.read(saveSyncServiceProvider);
    if (syncService != null) {
      // Push local saves first so nothing is lost, then pull cloud save
      final syncMode = ref.read(retroarchSyncModeProvider);
      await syncService.pushSaves(game, existingRomPath, syncMode: syncMode);
      if (!context.mounted) return;
      try {
        final pulled = await syncService.pullSave(game, existingRomPath);
        if (!context.mounted) return;
        if (pulled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cloud save restored'), duration: Duration(seconds: 2)),
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Save Sync Warning'),
            content: Text('${e.toString().replaceAll('Exception: ', '')}\n\nYou can still play, but your cloud save will not be restored. After playing once, exit the game and sync saves manually.'),
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
      await strategy.launch(game, existingRomPath);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Launch failed: $e')),
      );
    }
  }

  Future<void> _handleSyncSaves(BuildContext context, WidgetRef ref, Game game) async {
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

  void _startDownload(BuildContext context, WidgetRef ref, game) {
    final service = ref.read(rommServiceProvider);
    if (service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to RomM')),
      );
      return;
    }
    final url = service.getDownloadUrl(game);
    final basicAuth = 'Basic ${base64Encode(utf8.encode('${service.config.username}:${service.config.password}'))}';
    final headers = <String, String>{'Authorization': basicAuth};
    ref.read(downloadProvider.notifier).startDownload(game, url, headers: headers);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading ${game.name}...')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platformsAsync = ref.watch(platformsProvider);
    final selectedPlatformId = ref.watch(selectedPlatformIdProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final gamesAsync = ref.watch(allGamesProvider);
    final filteredGames = ref.watch(filteredGamesProvider);
    final cardAspectRatio = ref.watch(cardAspectRatioProvider);
    final rommConfigAsync = ref.watch(rommConfigProvider);
    final directoryServiceAsync = ref.watch(directoryServiceProvider);

    // Build AppBar title: "Freegosy • hostname • N games"
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
      body: Column(
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
              loading: () => const Center(child: CircularProgressIndicator()),
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
                final countDisplayText = (selectedPlatformId == null && searchQuery.isEmpty)
                    ? 'Showing all $gamesCount games'
                    : 'Showing $gamesCount games';

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          countDisplayText,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ),
                    Expanded(
                      child: filteredGames.isEmpty
                          ? const Center(child: Text('No games found'))
                          : GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                childAspectRatio: cardAspectRatio,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: filteredGames.length,
                              itemBuilder: (context, index) {
                                final game = filteredGames[index];
                                final dirService = directoryServiceAsync.asData?.value;
                                if (dirService == null) {
                                  return GameCard(
                                    game: game,
                                    onDownload: () => _startDownload(context, ref, game),
                                    onLaunch: () => _handleLaunch(context, ref, game),
                                    onSyncSaves: () => _handleSyncSaves(context, ref, game),
                                  );
                                }
                                return FutureBuilder<bool>(
                                  future: dirService.isRomDownloaded(game),
                                  builder: (context, snapshot) {
                                    return GameCard(
                                      game: game,
                                      isDownloaded: snapshot.data ?? false,
                                      onDownload: () => _startDownload(context, ref, game),
                                      onLaunch: () => _handleLaunch(context, ref, game),
                                      onSyncSaves: () => _handleSyncSaves(context, ref, game),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
