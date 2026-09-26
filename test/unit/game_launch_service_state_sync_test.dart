import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/game_launch_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/save/backup_repository.dart';
import 'package:freegosy/core/save/backup_service.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/save/state_sync_service.dart';
import 'package:freegosy/core/storage/app_preferences.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_romm_states_api.dart';

/// A StateSyncService whose pushStates throws, like an unexpected failure.
class _ThrowingStateSync extends StateSyncService {
  _ThrowingStateSync(AppPreferences prefs)
      : super(FakeRommStatesApi(), prefs, (game, {emulatorId}) => null);

  @override
  Future<StateSyncResult> pushStates(Game game, String romPath,
          {DateTime? sessionStart, String? emulatorId}) async =>
      throw StateError('push exploded');
}

/// A StateSyncService whose pushStates reports two conflicts and remembers
/// what it was asked to push.
class _ConflictingStateSync extends StateSyncService {
  _ConflictingStateSync(AppPreferences prefs)
      : super(FakeRommStatesApi(), prefs, (game, {emulatorId}) => null);

  DateTime? seenSessionStart;
  String? seenEmulatorId;
  String? seenRomPath;

  @override
  Future<StateSyncResult> pushStates(Game game, String romPath,
      {DateTime? sessionStart, String? emulatorId}) async {
    seenSessionStart = sessionStart;
    seenEmulatorId = emulatorId;
    seenRomPath = romPath;
    StateConflict conflict(String name) => StateConflict(
          game: game,
          romPath: romPath,
          emulatorId: emulatorId,
          fileName: name,
          localPath: name,
          cloudStateId: 1,
          cloudUpdatedAt: null,
          localTime: DateTime(2026, 1, 1),
          cloudTime: DateTime(2026, 1, 1),
        );
    return StateSyncResult(conflicts: [conflict('a.p2s'), conflict('b.p2s')]);
  }
}

/// A process that has already exited with code 0.
class _ExitedProcess implements io.Process {
  @override
  Future<int> get exitCode => Future.value(0);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A SaveSyncService whose pushSaves only records that it ran.
class _RecordingSaveSync extends SaveSyncService {
  _RecordingSaveSync(super.romm, super.dirs, super.registry, super.prefs, this.log);
  final List<String> log;

  @override
  Future<bool> pushSaves(Game game, String romPath,
      {DateTime? sessionStart,
      String syncMode = 'both',
      bool force = false,
      String? coreOverride,
      String? emulatorId}) async {
    log.add('push');
    return true;
  }
}

/// A GameLaunchService whose save push appends 'push' to [log].
Future<GameLaunchService> _launchServiceLogging(List<String> log) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
  final dirService = DirectoryService(prefs);
  final registry = StrategyRegistry(dirService, prefs);
  final rommService = RommService(
    RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', apiKey: 'k'),
    dio: Dio(BaseOptions(baseUrl: 'https://romm.example.com')),
    skipConnectivityCheck: true,
  );
  return GameLaunchService(
    directoryService: dirService,
    strategyRegistry: registry,
    saveSyncService: _RecordingSaveSync(rommService, dirService, registry, prefs, log),
    backupService: BackupService(),
    backupRepository: BackupRepository(),
    prefs: prefs,
  );
}

/// A GameLaunchService wired to real (in-memory) collaborators and [stateSync].
Future<GameLaunchService> _launchServiceWith(
    StateSyncService? Function(AppPreferences prefs) stateSync) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
  final dirService = DirectoryService(prefs);
  final registry = StrategyRegistry(dirService, prefs);
  final rommService = RommService(
    RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', apiKey: 'k'),
    dio: Dio(BaseOptions(baseUrl: 'https://romm.example.com')),
    skipConnectivityCheck: true,
  );
  return GameLaunchService(
    directoryService: dirService,
    strategyRegistry: registry,
    saveSyncService: SaveSyncService(rommService, dirService, registry, prefs),
    backupService: BackupService(),
    backupRepository: BackupRepository(),
    prefs: prefs,
    rommService: rommService,
    stateSyncService: stateSync(prefs),
  );
}

GameSession _session() => GameSession(
      process: null,
      sessionStart: DateTime(2026, 1, 1),
      emulatorId: 'pcsx2',
      activityTrackerFuture: Future.value(null),
    );

final _game = Game(id: '42', name: 'Ico (SCUS-97113)', platformSlug: 'ps2', fileSize: 0);

void main() {
  test('LaunchResult reports zero state conflicts by default', () {
    const result = LaunchResult(syncOk: true);

    expect(result.stateConflictCount, 0);
  });

  test('LaunchResult carries a state conflict count', () {
    const result = LaunchResult(syncOk: true, stateConflictCount: 2);

    expect(result.stateConflictCount, 2);
  });

  test('GameLaunchService accepts an optional StateSyncService', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final dirService = DirectoryService(prefs);
    final registry = StrategyRegistry(dirService, prefs);
    final rommService = RommService(
      RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', apiKey: 'k'),
      dio: Dio(BaseOptions(baseUrl: 'https://romm.example.com')),
      skipConnectivityCheck: true,
    );
    final saveSync = SaveSyncService(rommService, dirService, registry, prefs);

    final service = GameLaunchService(
      directoryService: dirService,
      strategyRegistry: registry,
      saveSyncService: saveSync,
      backupService: BackupService(),
      backupRepository: BackupRepository(),
      prefs: prefs,
      rommService: rommService,
      stateSyncService: StateSyncService(FakeRommStatesApi(), prefs, saveSync.getStrategyForGame),
    );

    expect(service.stateSyncService, isNotNull);
  });

  group('pushStatesAfterExit', () {
    test('a throwing push is swallowed and counts as no conflicts', () async {
      final service = await _launchServiceWith(_ThrowingStateSync.new);

      final count = await service.pushStatesAfterExit(_session(), _game, 'Ico.iso');

      expect(count, 0);
    });

    test('returns the conflict count and pushes for the session that just ended', () async {
      late _ConflictingStateSync stateSync;
      final service = await _launchServiceWith((prefs) => stateSync = _ConflictingStateSync(prefs));
      final session = _session();

      final count = await service.pushStatesAfterExit(session, _game, 'Ico.iso');

      expect(count, 2);
      expect(stateSync.seenSessionStart, session.sessionStart);
      expect(stateSync.seenEmulatorId, 'pcsx2');
      expect(stateSync.seenRomPath, 'Ico.iso');
    });

    test('without a state sync service it does nothing', () async {
      final service = await _launchServiceWith((_) => null);

      final count = await service.pushStatesAfterExit(_session(), _game, 'Ico.iso');

      expect(count, 0);
    });
  });
  group('awaitExitAndSync onExited', () {
    GameSession exited() => GameSession(
          process: _ExitedProcess(),
          sessionStart: DateTime(2026, 1, 1),
          emulatorId: 'pcsx2',
          activityTrackerFuture: Future.value(null),
        );

    test('is called once, right after the exit and before the save push', () async {
      final log = <String>[];
      final service = await _launchServiceLogging(log);

      final result = await service.awaitExitAndSync(exited(), _game, 'Ico.iso',
          syncMode: 'both', onExited: () => log.add('exited'));

      expect(result, isNotNull);
      expect(log, ['exited', 'push']);
    });

    test('a throwing onExited does not stop the pipeline', () async {
      final log = <String>[];
      final service = await _launchServiceLogging(log);

      final result = await service.awaitExitAndSync(exited(), _game, 'Ico.iso',
          syncMode: 'both', onExited: () => throw StateError('listener exploded'));

      expect(result, isNotNull);
      expect(log, ['push']);
    });
  });
}
