import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/library_provider.dart'; // Ensure this import is correct
import '../../providers/download_provider.dart';
import '../../providers/romm_provider.dart';
import '../widgets/game_card.dart';
import '../widgets/platform_filter_bar.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert'; // Ensure this import is present

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch platforms to populate the filter bar
    final platformsAsync = ref.watch(platformsProvider);
    // Watch the selected platform ID
    final selectedPlatformId = ref.watch(selectedPlatformIdProvider);
    // Watch the search query
    final searchQuery = ref.watch(searchQueryProvider);

    // Watch allGamesProvider for the overall loading/error state of the initial fetch
    final gamesAsync = ref.watch(allGamesProvider);
    // Watch filteredGamesProvider for the actual list of games to display
    final filteredGames = ref.watch(filteredGamesProvider);

    // Get card aspect ratio from provider
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
                String countDisplayText;
                if (selectedPlatformId == null && searchQuery.isEmpty) {
                  countDisplayText = 'Showing all $gamesCount games';
                } else {
                  countDisplayText = 'Showing $gamesCount games';
                }

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
                                  onDownload: () async {
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
                                      SnackBar(content: Text('Starting download: ${game.name}')),
                                    );
                                  },
                                  onLaunch: () async { // Make callback async
                                    final registry = ref.read(strategyRegistryProvider);
                                    final strategy = registry?.getStrategyForSlug(game.platformSlug ?? '');
                                    if (strategy == null) {
                                      ScaffoldMessenger.of(context).showSnackBar( // Removed if (mounted)
                                        SnackBar(content: Text('No emulator configured for ${game.platformDisplayName ?? game.platformSlug}')),
                                      );
                                      return;
                                    }
                                    final dir = await ref.read(directoryServiceProvider.future);
                                    final romPath = await dir?.getRomFilePath(game) ?? '';
                                    if (romPath.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar( // Removed if (mounted)
                                        const SnackBar(content: Text('Could not determine ROM path')),
                                      );
                                      return;
                                    }
                                    try {
                                      await strategy.launch(game, romPath);
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar( // Removed if (mounted)
                                        SnackBar(content: Text('Launch failed: $e')),
                                      );
                                    }
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
