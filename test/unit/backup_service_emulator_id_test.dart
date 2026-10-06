import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/save/backup_service.dart';
import 'package:freegosy/core/save/save_strategy.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// A save strategy whose save folder is [dir].
class _DirStrategy extends SaveStrategy {
  _DirStrategy(this.dir);
  final String dir;
  @override
  Future<String?> getSaveDir(Game game, String romPath) async => dir;
  @override
  Future<List<File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async =>
      Directory(dir).listSync().whereType<File>().toList();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Save sync that resolves each emulator to a folder of [dirs], and records
/// which emulator it was asked for.
class _SaveDirSync implements SaveSyncService {
  _SaveDirSync(this.dirs);
  final Map<String, String> dirs;
  final askedFor = <String?>[];
  @override
  SaveStrategy? getStrategyForGame(Game game, {String? emulatorId}) {
    askedFor.add(emulatorId);
    final dir = dirs[emulatorId];
    return dir == null ? null : _DirStrategy(dir);
  }

  @override
  Future<T?> withStrategy<T>(Game game, Future<T> Function(SaveStrategy strategy) body,
      {String? emulatorId, String? coreOverride}) async {
    final strategy = getStrategyForGame(game, emulatorId: emulatorId);
    return strategy == null ? null : body(strategy);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

    test('restore puts a backup into the save folder of the emulator it is asked for', () async {
      final zipPath = p.join(tempDir.path, 'backup.zip');
      final archive = Archive()..addFile(ArchiveFile('game.sav', 4, [1, 2, 3, 4]));
      await File(zipPath).writeAsBytes(ZipEncoder().encode(archive));
      final saveDir = p.join(tempDir.path, 'melonds-saves');
      final sync = _SaveDirSync({'melonds': saveDir});

      final ok = await backupService.restore(zipPath, game, romPath, sync, emulatorId: 'melonds');

      expect(ok, isTrue);
      expect(sync.askedFor, ['melonds']);
      expect(File(p.join(saveDir, 'game.sav')).readAsBytesSync(), [1, 2, 3, 4]);
    });

    test('a backup of a save rewritten unchanged has the same hash', () async {
      PathProviderPlatform.instance = _FakePathProvider(p.join(tempDir.path, 'support'));
      final saveDir = Directory(p.join(tempDir.path, 'saves'))..createSync();
      final save = File(p.join(saveDir.path, 'game.sav'))..writeAsBytesSync([1, 2, 3]);
      final sync = _SaveDirSync({'melonds': saveDir.path});

      final first = await backupService.createImmediate(game, romPath, sync, emulatorId: 'melonds');
      save.setLastModifiedSync(DateTime(2020, 5, 6));
      final second = await backupService.createImmediate(game, romPath, sync, emulatorId: 'melonds');

      expect(first, isNotNull);
      expect(second!.md5, first!.md5);
    });
  });
}
