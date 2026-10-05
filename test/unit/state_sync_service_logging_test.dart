import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_state.dart';
import 'package:freegosy/core/save/state_sync_record.dart';
import 'package:freegosy/core/save/state_sync_service.dart';

import '../helpers/fake_romm_states_api.dart';
import '../helpers/state_sync_test_env.dart';

/// Captures every debugPrint of the current test, in order.
List<String> _captureLogs() {
  final logs = <String>[];
  final old = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logs.add(message);
  };
  addTearDown(() => debugPrint = old);
  return logs;
}

void main() {
  late StateSyncTestEnv env;

  setUp(() async => env = await StateSyncTestEnv.create());
  tearDown(() => env.dispose());

  group('skip reasons', () {
    test('a switched-off emulator says so, with its key, on pull and push', () async {
      final disabled = await StateSyncTestEnv.create(enabled: false);
      addTearDown(disabled.dispose);
      await disabled.writeState(stateFileA, stateBytes(1));
      final logs = _captureLogs();

      final pull = await disabled.service.pullStates(disabled.game, disabled.romPath);
      final push = await disabled.service.pushStates(disabled.game, disabled.romPath);

      expect(pull.downloaded, 0);
      expect(push.uploaded, 0);
      const line = "[StateSync] Ico (SCUS-97113): state sync is off for 'pcsx2': "
          'switch it on in Settings > Emulators';
      expect(logs.where((l) => l == line), hasLength(2), reason: 'one per operation: $logs');
    });

    test('a strategy without StateSyncCapable says so, with the emulator id', () async {
      final incapable = StateSyncService(FakeRommStatesApi(), env.pcsx2.prefs,
          (game, {emulatorId, coreOverride}) => null);
      final logs = _captureLogs();

      final pull = await incapable.pullStates(env.game, env.romPath, emulatorId: 'duckstation');
      final push = await incapable.pushStates(env.game, env.romPath, emulatorId: 'duckstation');

      expect(pull.skipped, isTrue);
      expect(push.skipped, isTrue);
      const line = "[StateSync] Ico (SCUS-97113): no state-sync support for emulator "
          "'duckstation' (strategy none)";
      expect(logs.where((l) => l == line), hasLength(2), reason: '$logs');
    });
  });

  group('pull', () {
    test('a download logs the start, the file and the summary', () async {
      env.api.seed('42', stateFileA, stateBytes(1));
      final logs = _captureLogs();

      final result = await env.service.pullStates(env.game, env.romPath);

      expect(result.downloaded, 1);
      expect(logs, containsAllInOrder([
        '[StateSync] pull Ico (SCUS-97113) (rom 42, emulator pcsx2): '
            'states folder ${env.statesDir}',
        '[StateSync] pull: RomM lists 1 state(s), 1 match this game',
        '[StateSync] downloaded $stateFileA',
        '[StateSync] pull done: downloaded=1 restamped=0 conflicts=0',
      ]));
    });

    test('an empty server list is reported explicitly', () async {
      final logs = _captureLogs();

      await env.service.pullStates(env.game, env.romPath);

      expect(logs, contains(
          '[StateSync] pull: RomM lists 0 state(s), 0 match this game (nothing to download)'));
      expect(logs, contains('[StateSync] pull done: downloaded=0 restamped=0 conflicts=0'));
    });

    test('states of other games are listed but not counted as matching', () async {
      env.api.seed('42', stateFileA, stateBytes(1));
      env.api.seed('42', 'OTHER (DEADBEEF).01.p2s', stateBytes(2));
      final logs = _captureLogs();

      await env.service.pullStates(env.game, env.romPath);

      expect(logs, contains('[StateSync] pull: RomM lists 2 state(s), 1 match this game'));
    });

    test('an unchanged state and a locally changed one each say what happened', () async {
      env.api.seed('42', stateFileA, stateBytes(1));
      await env.service.pullStates(env.game, env.romPath);
      final logs = _captureLogs();

      await env.service.pullStates(env.game, env.romPath);
      await env.writeState(stateFileA, stateBytes(2));
      await env.service.pullStates(env.game, env.romPath);

      expect(logs, contains('[StateSync] unchanged $stateFileA'));
      expect(logs, contains(
          '[StateSync] kept local $stateFileA (changed locally, will upload after exit)'));
    });

    test('identical bytes with no shared history are linked', () async {
      env.api.seed('42', stateFileA, stateBytes(1));
      await env.writeState(stateFileA, stateBytes(1));
      final logs = _captureLogs();

      await env.service.pullStates(env.game, env.romPath);

      expect(logs, contains('[StateSync] linked $stateFileA (identical bytes)'));
    });

    test('a state changed on both sides is a conflict, and the summary counts it', () async {
      final seeded = env.api.seed('42', stateFileA, stateBytes(1));
      await env.service.pullStates(env.game, env.romPath);
      await env.writeState(stateFileA, stateBytes(3));
      env.api.touch(seeded.id, stateBytes(2));
      final logs = _captureLogs();

      final result = await env.service.pullStates(env.game, env.romPath);

      expect(result.conflicts, hasLength(1));
      expect(logs, contains('[StateSync] conflict $stateFileA (changed on both sides)'));
      expect(logs, contains('[StateSync] pull done: downloaded=0 restamped=0 conflicts=1'));
    });

    test('RomM re-stamping identical bytes is logged as restamped, counted, and writes nothing', () async {
      await env.writeState(stateFileA, stateBytes(1));
      await env.service.pushStates(env.game, env.romPath); // POST: state id 1
      final file = env.stateFile(stateFileA);
      final before = file.lastModifiedSync();
      final syncedAt = (await env.api.listStates('42')).single.updatedAt;
      env.api.touch(1, stateBytes(1)); // updated_at moves, the bytes do not
      final touchedAt = (await env.api.listStates('42')).single.updatedAt;
      final logs = _captureLogs();

      final result = await env.service.pullStates(env.game, env.romPath);

      expect(result.downloaded, 0);
      expect(logs.where((l) => l.startsWith('[StateSync] restamped $stateFileA (state id 1): ')),
          hasLength(1), reason: '$logs');
      final line = logs.firstWhere((l) => l.startsWith('[StateSync] restamped '));
      expect(line, endsWith('updated_at changed (was $syncedAt, now $touchedAt), '
          'the bytes are identical so nothing was written'));
      expect(logs, contains('[StateSync] pull done: downloaded=0 restamped=1 conflicts=0'));
      expect(file.readAsBytesSync(), stateBytes(1));
      expect(file.lastModifiedSync(), before, reason: 'nothing was written to disk');

      logs.clear();
      await env.service.pullStates(env.game, env.romPath);
      expect(logs.where((l) => l.startsWith('[StateSync] restamped ')), isEmpty,
          reason: 'the record was re-stamped, so the next pull has nothing to report: $logs');
    });

    test('a pull right after a push has nothing restamped and nothing downloaded', () async {
      await env.writeState(stateFileA, stateBytes(1));
      await env.service.pushStates(env.game, env.romPath);
      final logs = _captureLogs();

      final result = await env.service.pullStates(env.game, env.romPath);

      expect(result.downloaded, 0);
      expect(logs.where((l) => l.startsWith('[StateSync] restamped ')), isEmpty, reason: '$logs');
      expect(logs, contains('[StateSync] unchanged $stateFileA'));
      expect(logs, contains('[StateSync] pull done: downloaded=0 restamped=0 conflicts=0'));
    });

    group('restampedLine names only what changed', () {
      const record = StateSyncRecord(rommStateId: 7, lastSyncedHash: 'h', serverUpdatedAt: 'T1');
      const tail = 'the bytes are identical so nothing was written';

      test('updated_at only', () {
        expect(
            StateSyncService.restampedLine(
                'a.p2s', RommState(id: 7, fileName: 'a.p2s', updatedAt: 'T2'), record),
            '[StateSync] restamped a.p2s (state id 7): updated_at changed (was T1, now T2), $tail');
      });

      test('state id only, with an identical updated_at', () {
        expect(
            StateSyncService.restampedLine(
                'a.p2s', RommState(id: 9, fileName: 'a.p2s', updatedAt: 'T1'), record),
            '[StateSync] restamped a.p2s (state id 9): state id changed (was 7, now 9), $tail');
      });

      test('both', () {
        expect(
            StateSyncService.restampedLine(
                'a.p2s', RommState(id: 9, fileName: 'a.p2s', updatedAt: 'T2'), record),
            '[StateSync] restamped a.p2s (state id 9): state id changed (was 7, now 9) and '
            'updated_at changed (was T1, now T2), $tail');
      });
    });

    test('a pull that stops early says so in the summary', () async {
      env.api.seed('42', stateFileA, stateBytes(1));
      env.api.failDownloads = true;
      final logs = _captureLogs();

      await env.service.pullStates(env.game, env.romPath);

      expect(logs, contains(
          '[StateSync] pull done: downloaded=0 restamped=0 conflicts=0 (stopped early: a download failed)'));
    });
  });

  group('push', () {
    test('an upload logs the start, the file with its method and id, and the summary', () async {
      await env.writeState(stateFileA, stateBytes(1));
      final logs = _captureLogs();

      final result = await env.service.pushStates(env.game, env.romPath);

      expect(result.uploaded, 1);
      expect(logs, containsAllInOrder([
        '[StateSync] push Ico (SCUS-97113) (rom 42): 1 of 1 local state(s) eligible '
            '(any modification time, at least 100 bytes)',
        '[StateSync] uploaded $stateFileA (POST, id 1)',
        '[StateSync] push done: uploaded=1 conflicts=0',
      ]));
    });

    test('nothing modified in the session says so', () async {
      final now = DateTime.now();
      await env.writeState(stateFileA, stateBytes(1),
          modified: now.subtract(const Duration(days: 1)));
      final logs = _captureLogs();
      final start = now.subtract(const Duration(minutes: 5));

      final result = await env.service.pushStates(env.game, env.romPath, sessionStart: start);

      expect(result.uploaded, 0);
      expect(logs, contains('[StateSync] push Ico (SCUS-97113) (rom 42): '
          '0 of 1 local state(s) eligible '
          '(modified since ${start.toIso8601String()}, at least 100 bytes)'));
      expect(logs, contains(
          '[StateSync] push: nothing to upload '
          '(no matching state of at least 100 bytes was modified this session)'));
    });

    test('a state under the minimum size is counted out, and the line says why', () async {
      await env.writeState(stateFileA, List.filled(50, 1));
      final logs = _captureLogs();

      final result = await env.service.pushStates(env.game, env.romPath);

      expect(result.uploaded, 0);
      expect(logs, contains('[StateSync] push Ico (SCUS-97113) (rom 42): 0 of 1 local state(s) '
          'eligible (any modification time, at least 100 bytes)'));
      expect(logs, contains('[StateSync] push: nothing to upload '
          '(no matching state of at least 100 bytes found)'));
    });

    test('a changed state is updated with PUT, an untouched one is unchanged', () async {
      await env.writeState(stateFileA, stateBytes(1));
      await env.writeState(stateFileB, stateBytes(2));
      await env.service.pushStates(env.game, env.romPath);
      await env.writeState(stateFileA, stateBytes(3));
      final logs = _captureLogs();

      await env.service.pushStates(env.game, env.romPath);

      expect(logs.where((l) => l.startsWith('[StateSync] uploaded $stateFileA (PUT, id ')),
          hasLength(1), reason: '$logs');
      expect(logs, contains('[StateSync] unchanged $stateFileB'));
      expect(logs, contains('[StateSync] push done: uploaded=1 conflicts=0'));
    });

    test('identical bytes with no shared history are linked, not uploaded', () async {
      env.api.seed('42', stateFileA, stateBytes(1));
      await env.writeState(stateFileA, stateBytes(1));
      final logs = _captureLogs();

      await env.service.pushStates(env.game, env.romPath);

      expect(logs, contains('[StateSync] linked $stateFileA (identical bytes)'));
      expect(logs, contains('[StateSync] push done: uploaded=0 conflicts=0'));
    });

    test('a state changed on both sides is a conflict', () async {
      final seeded = env.api.seed('42', stateFileA, stateBytes(1));
      await env.service.pullStates(env.game, env.romPath);
      await env.writeState(stateFileA, stateBytes(3));
      env.api.touch(seeded.id, stateBytes(2));
      final logs = _captureLogs();

      final result = await env.service.pushStates(env.game, env.romPath);

      expect(result.conflicts, hasLength(1));
      expect(logs, contains('[StateSync] conflict $stateFileA (changed on both sides)'));
      expect(logs, contains('[StateSync] push done: uploaded=0 conflicts=1'));
    });

    test('a server copy that vanished before the update is re-created', () async {
      await env.writeState(stateFileA, stateBytes(1));
      await env.service.pushStates(env.game, env.romPath);
      await env.writeState(stateFileA, stateBytes(2));
      env.api.nextUpdateIs404 = true;
      final logs = _captureLogs();

      await env.service.pushStates(env.game, env.romPath);

      expect(logs, contains(
          '[StateSync] uploaded $stateFileA (POST, id 2) - re-created: state 1 is gone from RomM'));
    });
  });

  group('resolveConflict', () {
    late StateConflict conflict;

    setUp(() async {
      final seeded = env.api.seed('42', stateFileA, stateBytes(1));
      await env.service.pullStates(env.game, env.romPath);
      await env.writeState(stateFileA, stateBytes(3));
      env.api.touch(seeded.id, stateBytes(2));
      conflict = (await env.service.pullStates(env.game, env.romPath)).conflicts.single;
    });

    test('keep local logs the choice and the upload', () async {
      final logs = _captureLogs();

      expect(await env.service.resolveConflict(conflict, choice: 'local'), isTrue);

      expect(logs, containsAllInOrder([
        '[StateSync] resolve $stateFileA: keep local',
        '[StateSync] resolve $stateFileA: keep local -> uploaded',
      ]));
    });

    test('keep cloud logs the choice and the restore', () async {
      final logs = _captureLogs();

      expect(await env.service.resolveConflict(conflict, choice: 'cloud'), isTrue);

      expect(logs, containsAllInOrder([
        '[StateSync] resolve $stateFileA: keep cloud',
        '[StateSync] resolve $stateFileA: keep cloud -> restored',
      ]));
    });

    test('an unknown choice logs that nothing was done, and no outcome', () async {
      final logs = _captureLogs();

      expect(await env.service.resolveConflict(conflict, choice: 'nope'), isFalse);

      expect(logs, contains("[StateSync] resolve $stateFileA: unknown choice 'nope' — nothing done"));
      expect(logs.where((l) => l.contains('->')), isEmpty, reason: '$logs');
    });
  });

  group('availabilityReason', () {
    Future<StateSyncService> serviceFor(String kind) async {
      switch (kind) {
        case 'enabled':
          return env.service;
        case 'disabled':
          final disabled = await StateSyncTestEnv.create(enabled: false);
          addTearDown(disabled.dispose);
          return disabled.service;
        default:
          return StateSyncService(FakeRommStatesApi(), env.pcsx2.prefs, (game, {emulatorId, coreOverride}) => null);
      }
    }

    const cases = <(String, String?, String)>[
      ('enabled', null, 'available'),
      ('enabled', 'pcsx2', 'available'),
      ('disabled', null, "state sync is off for 'pcsx2': switch it on in Settings > Emulators"),
      ('disabled', 'pcsx2', "state sync is off for 'pcsx2': switch it on in Settings > Emulators"),
      ('incapable', null, "no state-sync support for emulator 'unknown' (strategy none)"),
      ('incapable', 'duckstation', "no state-sync support for emulator 'duckstation' (strategy none)"),
    ];

    for (final (kind, emulatorId, reason) in cases) {
      test('$kind service, emulator ${emulatorId ?? 'unset'}: "$reason" agrees with isAvailableFor',
          () async {
        final service = await serviceFor(kind);

        expect(service.availabilityReason(env.game, emulatorId: emulatorId), reason);
        expect(service.isAvailableFor(env.game, emulatorId: emulatorId), reason == 'available');
      });
    }
  });
}
