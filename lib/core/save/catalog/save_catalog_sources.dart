import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../emulator/retroarch_core_list.dart';
import '../../emulator/strategy_registry.dart';
import '../../romm/romm_models.dart';
import '../../romm/romm_service.dart';
import '../backup_repository.dart';
import '../save_sync_service.dart';
import '../strategies/retroarch_save_strategy.dart';
import 'save_catalog.dart';
import 'save_entry.dart';
import 'save_maker.dart';

/// Where a game's saves are read from.
abstract class SaveCatalogSources {
  /// One row per installed emulator for the game's platform that has a save.
  Future<List<SaveEntry>> localSaves(Game game, String romPath);

  List<SaveEntry> backups(Game game);

  /// RomM's save list; null when RomM can't be listed.
  Future<List<Map<String, dynamic>>?> rommSaves(Game game);

  /// Emulator ids for telling a RomM save's maker.
  Set<String> get emulatorIds;
}

bool _isStateFile(String name) {
  final n = name.toLowerCase();
  return n.endsWith('.state') || n.contains('.state.') || RegExp(r'\.state\d+$').hasMatch(n);
}

Future<SaveCatalog> loadSaveCatalog(Game game, String romPath, SaveCatalogSources sources) async {
  final results = await Future.wait([sources.localSaves(game, romPath), sources.rommSaves(game)]);
  final local = results[0] as List<SaveEntry>;
  final romm = results[1] as List<Map<String, dynamic>>?;
  return buildSaveCatalog(
    local: local,
    backups: sources.backups(game),
    romm: romm == null
        ? null
        : [
            for (final s in romm)
              if (!_isStateFile(s['file_name']?.toString() ?? ''))
                SaveEntry.fromRomm(s, emulatorIds: sources.emulatorIds),
          ],
  );
}

/// The saves Freegosy's services know about.
class LiveSaveCatalogSources implements SaveCatalogSources {
  LiveSaveCatalogSources({
    required this.sync,
    required this.registry,
    required this.backupRepository,
    required this.rommService,
    required this.installed,
  });

  final SaveSyncService sync;
  final StrategyRegistry registry;
  final BackupRepository backupRepository;
  final RommService? rommService;

  /// Emulator id → installed.
  final Map<String, bool> installed;

  @override
  Set<String> get emulatorIds => kKnownEmulatorIds;

  @override
  Future<List<SaveEntry>> localSaves(Game game, String romPath) async {
    final rows = <SaveEntry>[];
    final seen = <Object>{};
    final slug = game.platformSlug ?? '';
    for (final emulator in registry.getAllStrategiesForSlug(slug)) {
      if (installed[emulator.emulatorId] != true) continue;
      // RetroArch: the game's own core, then every core's own save (sorted
      // by core, each has its folder).
      final cores = <String?>[
        null,
        if (emulator.emulatorId == 'retroarch') ...getCoresForSlug(slug).map((c) => c.id),
      ];
      for (final core in cores) {
        // Under the save lock: another game's sync may be using the strategy.
        final row = await sync.withStrategy<SaveEntry?>(game, (strategy) async {
          if (strategy is! RetroArchSaveStrategy && !seen.add(strategy)) return null;
          try {
            final files = [
              for (final f in await strategy.getSaveFiles(game, romPath, syncMode: 'saves'))
                if (await f.exists()) f,
            ];
            if (files.isEmpty) return null;
            // The same files as an earlier row (one RetroArch folder for all cores).
            if (!seen.add((files.map((f) => p.normalize(f.path)).toList()..sort()).join('|'))) return null;
            io.File newest = files.first;
            var newestTime = await newest.lastModified();
            var size = 0;
            for (final f in files) {
              final t = await f.lastModified();
              if (t.isAfter(newestTime)) {
                newest = f;
                newestTime = t;
              }
              size += await f.length();
            }
            final maker = strategy is RetroArchSaveStrategy
                ? SaveMaker('retroarch', coreId: strategy.coreIdFor(game))
                : SaveMaker(emulator.emulatorId);
            return SaveEntry(
              source: SaveSource.local,
              fileName: p.basename(newest.path),
              savedAt: newestTime,
              maker: maker,
              tag: maker.tag,
              sizeBytes: size,
              sameAsRommId: await sync.rommCopyOfLocal(game, romPath, emulatorId: emulator.emulatorId, coreOverride: core),
              // As each sync mode would upload it ('both' adds states).
              contentHashes:
                  await sync.rommHashesOfLocal(game, romPath, emulatorId: emulator.emulatorId, coreOverride: core),
              sharedFile: await strategy.pullMustFinishBeforeLaunch(game, romPath),
            );
          } catch (e) {
            debugPrint('[SaveCatalog] ${emulator.emulatorId}: saves not listed ($e)');
            return null;
          }
        }, emulatorId: emulator.emulatorId, coreOverride: core);
        if (row != null) rows.add(row);
      }
    }
    return rows;
  }

  @override
  List<SaveEntry> backups(Game game) {
    try {
      return [
        for (final b in backupRepository.getEntries(game.id))
          SaveEntry(
            source: SaveSource.backup,
            fileName: p.basename(b.localZipPath),
            savedAt: b.timestamp,
            // Recorded as made, not read from a tag: RetroArch with its core.
            maker: b.emulatorId == null ? null : SaveMaker(b.emulatorId!, coreId: b.coreId),
            tag: b.coreId ?? b.emulatorId,
            sizeBytes: () {
              try {
                return io.File(b.localZipPath).lengthSync();
              } catch (_) {
                return null;
              }
            }(),
            backup: b,
          ),
      ];
    } catch (e) {
      debugPrint('[SaveCatalog] backups not listed ($e)');
      return const [];
    }
  }

  @override
  Future<List<Map<String, dynamic>>?> rommSaves(Game game) async {
    final romm = rommService;
    if (romm == null || romm.isOffline.value) return null;
    try {
      return await romm.getSavesListOrNull(game.id).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[SaveCatalog] RomM saves not listed ($e)');
      return null;
    }
  }
}
