import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/library_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/romm_provider.dart';
import '../widgets/game_card.dart';
import '../widgets/platform_filter_bar.dart';

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
    if (dir == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage service not available')),
      );
      return;
    }

    // Use smart file detection
    final existingRomPath = await dir.findExistingRomPath(game);
    final expectedRomPath = await dir.getRomFilePath(game);

    if (existingRomPath == null) {
      // ROM not found — show dialog with expected location
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

      if (shouldDownload == true) {
        _startDownload(context, ref, game);
      }
      return;
    }

    // ROM found — launch it
    try {
      await strategy.launch(game, existingRomPath);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Launch failed: $e')),
      );
    }
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
    final u = service.config.username;
    final p = service.config.password;
    final token = 'Basic ${base64Encode(utf8.encode('$u:$p'))}';
    final headers = <String, String>{'Authorization': token};
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

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
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
                                return GameCard(
                                  game: game,
                                  onDownload: () => _startDownload(context, ref, game),
                                  onLaunch: () => _handleLaunch(context, ref, game),
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