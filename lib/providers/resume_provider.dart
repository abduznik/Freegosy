import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../core/emulator/game_launch_service.dart';
import '../core/romm/romm_models.dart';
import '../core/save/resume_service.dart';
import '../core/storage/directory_service.dart';
import 'romm_provider.dart';
import 'shared_prefs_provider.dart';

/// Resume list service; null until the strategy registry and save sync are up.
final resumeServiceProvider = FutureProvider<ResumeService?>((ref) async {
  final registry = await ref.watch(strategyRegistryProvider.future);
  final saveSync = await ref.watch(saveSyncServiceProvider.future);
  if (registry == null || saveSync == null) return null;
  final romm = ref.watch(rommServiceProvider);
  return ResumeService(
    emulatorsFor: registry.getAllStrategiesForSlug,
    resolveSaveStrategy: saveSync.getStrategyForGame,
    prefs: ref.watch(appPreferencesProvider),
    api: romm,
    isOffline: () => romm?.isOffline.value == true,
  );
});

/// Family key: one resume list per game and per ROM resolution. Besides the
/// id it compares the fields that decide which ROM/emulator the list is built
/// from, so when the game page swaps in a fuller [Game] after a detail fetch
/// the list is rebuilt from it instead of staying on the first (thin) object.
@immutable
class ResumeKey {
  const ResumeKey(this.game);
  final Game game;
  @override
  bool operator ==(Object other) =>
      other is ResumeKey &&
      other.game.id == game.id &&
      other.game.platformSlug == game.platformSlug &&
      other.game.fsName == game.fsName &&
      other.game.fsExtension == game.fsExtension &&
      other.game.hasMultipleFiles == game.hasMultipleFiles &&
      other.game.files.length == game.files.length;
  @override
  int get hashCode => Object.hash(game.id, game.platformSlug, game.fsName, game.fsExtension,
      game.hasMultipleFiles, game.files.length);
}

/// The game's resume entries: local ones first, then merged with RomM.
/// Invalidate it after a launch exits and after a manual state sync.
final resumeEntriesProvider =
    StreamProvider.autoDispose.family<List<ResumeEntry>, ResumeKey>((ref, key) async* {
  final service = await ref.watch(resumeServiceProvider.future);
  final dir = await ref.watch(directoryServiceProvider.future);
  if (service == null || dir == null) {
    yield const [];
    return;
  }
  final launch = await ref.watch(gameLaunchServiceProvider.future);
  final romPaths = await resolveResumeRomPaths(key.game, dir, launch);
  if (romPaths.isEmpty) {
    yield const [];
    return;
  }
  yield* service.entriesFor(key.game, romPaths);
});

/// The ROM files [game]'s states are identified with (a state belongs to one
/// disc, its serial): the downloaded file itself, or for a folder every disc
/// image in it (playlists aside), sorted by path. A folder without disc images
/// falls back to the file launch would pick, then to its first non-.txt file.
/// Empty when not downloaded or nothing is found. Never throws.
Future<List<String>> resolveResumeRomPaths(
    Game game, DirectoryService dir, GameLaunchService? launch) async {
  try {
    final existing = await dir.findExistingRomPath(game);
    if (existing == null) return const [];
    if (!await io.Directory(existing).exists()) return [existing];
    final files = (await io.Directory(existing).list().toList())
        .whereType<io.File>()
        .map((f) => f.path)
        .toList()
      ..sort();
    final discs = files.where((f) => GameLaunchService.isDiscImageName(p.basename(f))).toList();
    if (discs.isNotEmpty) return discs;
    if (launch != null) {
      final resolved = await launch.resolveRomFileInDirectory(existing, game.platformSlug);
      if (await io.File(resolved).exists()) return [resolved];
    }
    final other = files.where((f) => !p.basename(f).toLowerCase().endsWith('.txt'));
    return other.isEmpty ? const [] : [other.first];
  } catch (e) {
    debugPrint('[Resume] cannot resolve the ROM paths for ${game.name}: $e');
    return const [];
  }
}
