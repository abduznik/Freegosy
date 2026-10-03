import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_models.dart';
import '../core/save/catalog/save_catalog.dart';
import '../core/save/catalog/save_catalog_sources.dart';
import 'romm_provider.dart';

/// Identifies a game for [saveCatalogProvider] (Game has no value equality).
class SaveCatalogKey {
  const SaveCatalogKey(this.game);
  final Game game;
  @override
  bool operator ==(Object other) => other is SaveCatalogKey && other.game.id == game.id && other.game.fsName == game.fsName;
  @override
  int get hashCode => Object.hash(game.id, game.fsName);
}

/// Every save of a game: this PC, backups, RomM. Re-read when invalidated
/// (the play screen and the Saves tab invalidate it when they open).
final saveCatalogProvider = FutureProvider.autoDispose.family<SaveCatalog, SaveCatalogKey>((ref, key) async {
  final sync = await ref.watch(saveSyncServiceProvider.future);
  final registry = await ref.watch(strategyRegistryProvider.future);
  final dirs = await ref.watch(directoryServiceProvider.future);
  final installed = await ref.watch(emulatorStatusProvider.future);
  if (sync == null || registry == null || dirs == null) {
    return const SaveCatalog(thisPc: [], backups: [], romm: [], rommOffline: true);
  }
  // Where the ROM is, as push and restore find it (a renamed or moved ROM too).
  final romPath = await dirs.findExistingRomPath(key.game) ?? await dirs.getRomFilePath(key.game);
  return loadSaveCatalog(
    key.game,
    romPath,
    LiveSaveCatalogSources(
      sync: sync,
      registry: registry,
      backupRepository: ref.read(backupRepositoryProvider),
      rommService: ref.watch(rommServiceProvider),
      installed: installed,
    ),
  );
});
