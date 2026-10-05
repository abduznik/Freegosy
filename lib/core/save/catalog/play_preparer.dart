import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../romm/romm_models.dart';
import '../backup_entry.dart';
import '../backup_repository.dart';
import '../backup_service.dart';
import '../save_sync_service.dart';
import 'save_entry.dart';
import 'save_maker.dart';

export '../save_sync_service.dart' show SaveChoiceException;

/// Puts the save the user chose in place before the game starts.
class PlayPreparer {
  PlayPreparer({required this.sync, required this.backups, required this.repository});

  final SaveSyncService sync;
  final BackupService backups;
  final BackupRepository repository;

  /// Makes [save] the save [target] starts with. The target's current save
  /// is backed up (and listed among the backups) first. Throws
  /// SaveChoiceException when it can't be done; the backup stays.
  Future<void> prepare(Game game, String romPath, SaveEntry save, {required SaveMaker target}) async {
    final maker = save.maker;
    if (save.source == SaveSource.local && maker?.emulatorId == target.emulatorId) {
      if (maker!.coreId == target.coreId) return;
      // RetroArch keeps one folder per core; nothing copies between them.
      throw SaveChoiceException('This save belongs to the ${maker.coreId ?? 'default'} core; pick that core to play it.');
    }
    // ROM folders hold only games: never write a save there.
    final saveDir = await sync.saveDirFor(game, romPath, emulatorId: target.emulatorId, coreOverride: target.coreId);
    if (saveDir != null && p.equals(p.normalize(saveDir), p.normalize(p.dirname(romPath)))) {
      throw SaveChoiceException("${target.emulatorId} keeps its saves in the game's folder, which holds only games. "
          'Set its save folder first.');
    }
    await backUp(game, romPath, target);
    switch (save.source) {
      case SaveSource.romm:
        await sync.restoreChosenSave(game, romPath, save.rommSave!,
            emulatorId: target.emulatorId, coreOverride: target.coreId);
      case SaveSource.backup:
        final ok = await backups.restore(save.backup!.localZipPath, game, romPath, sync,
            emulatorId: target.emulatorId, coreOverride: _coreOverride(target));
        if (!ok) throw SaveChoiceException("The backup from ${save.savedAt} couldn't be restored.");
      case SaveSource.local:
        final from = save.maker;
        if (from == null) throw SaveChoiceException("It isn't known which emulator made this save.");
        await sync.convertLocalSave(game, romPath,
            fromEmulatorId: from.emulatorId, fromTag: from.tag, emulatorId: target.emulatorId, coreOverride: target.coreId);
    }
  }

  /// RetroArch's core as the strategies take it (`mgba_libretro`).
  static String? _coreOverride(SaveMaker maker) => maker.coreId == null ? null : '${maker.coreId}_libretro';

  /// Backs up [who]'s current save for [game] and lists it among the
  /// game's backups; does nothing when there is no save, or when it is the
  /// same as the newest backup (which keeps the history from filling with
  /// copies). It is a local safety copy: marked synced, so the background
  /// queue never uploads it as the game's newest save.
  Future<void> backUp(Game game, String romPath, SaveMaker who) async {
    final result =
        await backups.createImmediate(game, romPath, sync, emulatorId: who.emulatorId, coreOverride: _coreOverride(who));
    if (result == null) return;
    final newest = repository.getEntries(game.id).firstOrNull;
    if (newest != null && newest.md5Hash == result.md5) {
      try {
        await io.File(result.zipPath).delete();
      } catch (_) {}
      return;
    }
    await repository.addEntry(
        game.id,
        BackupEntry(
            timestamp: DateTime.now(),
            md5Hash: result.md5,
            localZipPath: result.zipPath,
            isSynced: true,
            emulatorId: who.emulatorId,
            coreId: result.coreId ?? who.coreId));
    debugPrint('[PlayPreparer] backed up $who save of ${game.displayName}');
  }
}
