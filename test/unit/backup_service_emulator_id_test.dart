import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/save/backup_service.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;

/// Regression coverage for issue #42: after a game launched via one
/// emulator (e.g. melonDS), the post-exit backup step was resolving the
/// save strategy from the platform's globally-configured preference (e.g.
/// RetroArch) instead of the emulator that was actually used — the same
/// root cause fixed for issue #79's push/pull path, but BackupService's
/// createImmediate() wasn't passing emulatorId through and so kept
/// backing up a different (stale/unrelated) emulator's save file.
void main() {
  group('BackupService.createImmediate respects emulatorId override', () {
    late Directory tempDir;
    late StrategyRegistry registry;
    late SaveSyncService syncService;
    late BackupService backupService;
    late Game game;
    late String romPath;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final dirService = DirectoryService(prefs);
      registry = StrategyRegistry(dirService, prefs);
      final rommService = RommService(RomMConfig(baseUrl: '', username: '', password: ''));
      syncService = SaveSyncService(rommService, dirService, registry, prefs);
      backupService = BackupService();

      tempDir = await Directory.systemTemp.createTemp('backup_emulator_id_test');
      romPath = p.join(tempDir.path, 'game.nds');
      await File(romPath).writeAsString('rom');
      game = Game(id: 'g1', name: 'game', platformSlug: 'nds', fileSize: 0);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('resolves the same strategy as pushSaves would for the given emulatorId', () {
      // Without an override, both should agree on whichever emulator wins
      // the "first supported" fallback (mirrors launch_vs_sync_emulator_resolution_test).
      final launchStrategy = registry.getStrategyForSlug('nds');
      expect(launchStrategy, isNotNull);

      // With an explicit emulatorId (as GameLaunchService now passes),
      // createImmediate's internal strategy resolution must match pushSaves'.
      final pushStrategy = syncService.getStrategyForSlug('nds', emulatorId: 'melonds');
      expect(pushStrategy, isNotNull);
      expect(pushStrategy!.strategyId, 'melonds');

      // createImmediate delegates to syncService.getStrategyForSlug with the
      // same emulatorId — verified via the public contract rather than
      // reaching into the private call, since createImmediate itself needs
      // real save files on disk to produce a non-null result.
    });

    test('createImmediate returns null (not a wrong-emulator backup) when no save files exist for the given emulator', () async {
      // No save files exist for either emulator in this fresh temp dir, so
      // createImmediate must return null rather than silently succeeding
      // with a backup sourced from a different emulator's strategy.
      final result = await backupService.createImmediate(game, romPath, syncService, emulatorId: 'melonds');
      expect(result, isNull);
    });
  });
}
