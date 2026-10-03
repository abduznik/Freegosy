import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/game_launch_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/save/backup_entry.dart';
import 'package:freegosy/core/save/backup_repository.dart';
import 'package:freegosy/core/save/backup_service.dart';
import 'package:freegosy/core/save/save_strategy.dart';
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
      : super(FakeRommStatesApi(), prefs, (game, {emulatorId, coreOverride}) => null);

  @override
  Future<StateSyncResult> pushStates(Game game, String romPath,
          {DateTime? sessionStart, String? emulatorId, String? coreOverride}) async =>
      throw StateError('push exploded');
}

/// A StateSyncService whose pushStates reports two conflicts and remembers
/// what it was asked to push.
class _ConflictingStateSync extends StateSyncService {
  _ConflictingStateSync(AppPreferences prefs)
      : super(FakeRommStatesApi(), prefs, (game, {emulatorId, coreOverride}) => null);

  DateTime? seenSessionStart;
  String? seenEmulatorId;
  String? seenCoreOverride;
  String? seenRomPath;

  @override
  Future<StateSyncResult> pushStates(Game game, String romPath,
      {DateTime? sessionStart, String? emulatorId, String? coreOverride}) async {
    seenSessionStart = sessionStart;
    seenEmulatorId = emulatorId;
    seenCoreOverride = coreOverride;
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
  _RecordingSaveSync(super.romm, super.dirs, super.registry, super.prefs, this.log,
      {this.blockedReason, this.synced = false, List<String>? marked, this.steps, this.conflict = false, this.pushOk = true})
      : marked = marked ?? [];
  final List<String> log;

  /// Every save step and the save lock around them, in order.
  final List<String>? steps;

  /// What the last exclusive said it does.
  String? doing;

  @override
  Future<T> exclusive<T>(Future<T> Function() body, {String? doing}) async {
    this.doing = doing;
    steps?.add('lock');
    try {
      return await body();
    } finally {
      steps?.add('unlock');
    }
  }

  /// When set, pushSaves reports that saves can't be synced, like a
  /// strategy's saveSyncBlockedReason does.
  final String? blockedReason;

  /// When set, pushSaves reports that RomM has a newer save (a 409).
  final bool conflict;

  /// What pushSaves returns (false: nothing uploaded, e.g. RomM unreachable).
  final bool pushOk;

  /// Whether the save at exit is the content RomM has.
  final bool synced;

  /// The sync modes markSaveSynced was called with.
  final List<String> marked;

  @override
  Future<bool> saveIsSynced(Game game, String romPath,
          {required String emulatorId, required String syncMode, String? coreOverride}) async {
    steps?.add('isSynced');
    return synced;
  }

  @override
  Future<void> markSaveSynced(Game game, String romPath,
          {required String emulatorId, required String syncMode, String? coreOverride}) async {
    steps?.add('mark');
    marked.add(syncMode);
  }

  @override
  Future<bool> pushSaves(Game game, String romPath,
      {DateTime? sessionStart,
      String syncMode = 'both',
      bool force = false,
      String? coreOverride,
      String? emulatorId}) async {
    log.add('push');
    steps?.add('push');
    if (blockedReason != null) throw SaveSyncNotPossibleException(blockedReason!);
    if (conflict) throw SaveConflictException(game: game, localTime: DateTime(2026), cloudTime: DateTime(2026, 2));
    return pushOk;
  }
}

/// A GameLaunchService whose save push appends 'push' to [log].
Future<GameLaunchService> _launchServiceLogging(List<String> log,
    {String? blockedReason,
    bool synced = false,
    List<String>? marked,
    List<String>? steps,
    bool conflict = false,
    bool pushOk = true,
    BackupService? backupService,
    BackupRepository? backupRepository}) async {
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
    saveSyncService: _RecordingSaveSync(rommService, dirService, registry, prefs, log,
        blockedReason: blockedReason, synced: synced, marked: marked, steps: steps, conflict: conflict, pushOk: pushOk),
    backupService: backupService ?? BackupService(),
    backupRepository: backupRepository ?? BackupRepository(),
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
      stateSyncService: StateSyncService(FakeRommStatesApi(), prefs, saveSync.strategyForGame),
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

    test('pushes states from the core the session ran with', () async {
      late _ConflictingStateSync stateSync;
      final service = await _launchServiceWith((prefs) => stateSync = _ConflictingStateSync(prefs));
      await service.pushStatesAfterExit(_session(), _game, 'Ico.iso', coreOverride: 'mgba_libretro');
      expect(stateSync.seenCoreOverride, 'mgba_libretro');
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

    test('an upload RomM refuses (a newer save from another PC) is reported, not thrown away', () async {
      final service = await _launchServiceLogging([], conflict: true);
      final result = await service.awaitExitAndSync(exited(), _game, 'Ico.iso', syncMode: 'both');
      expect(result, isNotNull);
      expect(result!.saveConflict, isNotNull);
      expect(result.syncOk, isFalse);
    });

    test('the backup after a session RomM answered is not queued for upload; one RomM never saw is', () async {
      for (final (conflict, blocked, pushOk, queued) in [
        (true, null, true, false), // RomM has a newer save: the queue must not push this one over it
        (false, 'no', true, false),
        (false, null, true, false), // uploaded
        (false, null, false, true), // nothing reached RomM
      ]) {
        final repo = _MemoryBackups();
        final service = await _launchServiceLogging([],
            conflict: conflict, blockedReason: blocked, pushOk: pushOk, backupService: _OneBackup(), backupRepository: repo);
        await service.awaitExitAndSync(exited(), _game, 'Ico.iso', syncMode: 'both');
        expect(repo.added.single.isSynced, !queued, reason: 'conflict $conflict, blocked $blocked, pushed $pushOk');
      }
    });

    test('the save check, upload and synced mark run under one hold of the save lock', () async {
      final steps = <String>[];
      final service = await _launchServiceLogging([], steps: steps);
      await service.awaitExitAndSync(exited(), _game, 'Ico.iso', syncMode: 'both');
      expect(steps.take(5).toList(), ['lock', 'isSynced', 'push', 'mark', 'unlock']);
      expect((service.saveSyncService as _RecordingSaveSync).doing, "Syncing ${_game.displayName}'s save",
          reason: 'the play screen and Saves tab show it while they wait');
    });

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

    test('saves that cannot be synced are reported in the result, and the pipeline goes on', () async {
      final log = <String>[];
      final service = await _launchServiceLogging(log, blockedReason: 'one shared card');

      final result = await service.awaitExitAndSync(exited(), _game, 'Ico.iso',
          syncMode: 'both', onExited: () => log.add('exited'));

      expect(result, isNotNull);
      expect(result!.syncOk, isFalse);
      expect(result.saveSyncBlocked, 'one shared card');
      expect(log, ['exited', 'push']);
    });
  });

  group('awaitExitAndSync uploads only a save RomM does not have', () {
    GameSession exited() => GameSession(
          process: _ExitedProcess(),
          sessionStart: DateTime(2026, 1, 1),
          emulatorId: 'pcsx2',
          activityTrackerFuture: Future.value(null),
        );

    test('the save is what RomM has (e.g. an older RomM save, played without saving): no push', () async {
      final log = <String>[];
      final service = await _launchServiceLogging(log, synced: true);
      final result = await service.awaitExitAndSync(exited(), _game, 'Ico.iso', syncMode: 'both');
      expect(log, isEmpty);
      expect(result!.saveUnchanged, isTrue);
      expect(result.syncOk, isTrue);
    });

    test('any other save is pushed, and then counts as what RomM has', () async {
      final log = <String>[];
      final marked = <String>[];
      final service = await _launchServiceLogging(log, marked: marked);
      final result = await service.awaitExitAndSync(exited(), _game, 'Ico.iso', syncMode: 'both');
      expect(log, ['push']);
      expect(marked, ['both']);
      expect(result!.saveUnchanged, isFalse);
    });

    test('a push that could not run does not count the save as synced', () async {
      final marked = <String>[];
      final service = await _launchServiceLogging(<String>[], blockedReason: 'one shared card', marked: marked);
      await service.awaitExitAndSync(exited(), _game, 'Ico.iso', syncMode: 'both');
      expect(marked, isEmpty);
    });
  });
}

/// A backup service that always makes one backup.
class _OneBackup extends BackupService {
  @override
  Future<BackupResult?> createImmediate(Game game, String romPath, SaveSyncService syncService,
          {String? emulatorId, String? coreOverride}) async =>
      (zipPath: 'b.zip', md5: 'm', coreId: null);
}

/// Backups kept in memory.
class _MemoryBackups extends BackupRepository {
  final added = <BackupEntry>[];
  @override
  Future<bool> addUnlessSameAsNewest(String romId, BackupEntry entry) async {
    added.add(entry);
    return true;
  }
}
