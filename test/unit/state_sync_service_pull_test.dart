import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/state_sync_service.dart';
import 'package:path/path.dart' as p;

import '../helpers/state_sync_test_env.dart';

void main() {
  late StateSyncTestEnv env;

  setUp(() async => env = await StateSyncTestEnv.create());
  tearDown(() => env.dispose());

  test('does nothing while the toggle is off', () async {
    final disabled = await StateSyncTestEnv.create(enabled: false);
    addTearDown(disabled.dispose);
    disabled.api.seed('42', stateFileA, stateBytes(1));

    final result = await disabled.service.pullStates(disabled.game, disabled.romPath);

    expect(result.downloaded, 0);
    expect(disabled.api.calls, isEmpty);
    expect(disabled.stateFile(stateFileA).existsSync(), isFalse);
  });

  test('isAvailableFor needs a StateSyncCapable strategy AND the toggle', () async {
    expect(env.service.isAvailableFor(env.game), isTrue);
    final disabled = await StateSyncTestEnv.create(enabled: false);
    addTearDown(disabled.dispose);
    expect(disabled.service.isAvailableFor(disabled.game), isFalse);
  });

  test('downloads a server state that is missing locally (first sync on a new machine)', () async {
    env.api.seed('42', stateFileA, stateBytes(1));

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 1);
    expect(result.conflicts, isEmpty);
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(1));
  });

  test('reports the names of the files it downloaded', () async {
    env.api.seed('42', stateFileA, stateBytes(1));

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloadedFiles, {stateFileA});
    expect(StateSyncResult.none.downloadedFiles, isEmpty);

    final again = await env.service.pullStates(env.game, env.romPath);
    expect(again.downloadedFiles, isEmpty, reason: 'nothing new on the second pull');
  });

  test('ignores server states that belong to another game', () async {
    env.api.seed('42', 'SLUS-20312 (A1B2C3D4).01.p2s', stateBytes(1));

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 0);
    expect(env.api.calls, ['list']);
  });

  test('ignores server file names that try to escape the states folder', () async {
    env.api.seed('42', r'..\SCUS-97113 (A1B2C3D4).01.p2s', stateBytes(1));

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 0);
    expect(env.api.calls, ['list']);
  });

  test('rejects server content that is not a valid state', () async {
    env.api.seed('42', stateFileA, List.filled(200, 1)); // no zip header

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 0);
    expect(env.stateFile(stateFileA).existsSync(), isFalse);
  });

  test('a state deleted locally is not resurrected by the next pull', () async {
    env.api.seed('42', stateFileA, stateBytes(1));
    await env.service.pullStates(env.game, env.romPath);
    env.stateFile(stateFileA).deleteSync();
    env.api.calls.clear();

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 0);
    expect(env.stateFile(stateFileA).existsSync(), isFalse);
    expect(env.api.calls, ['list']);
  });

  test('replaces an unchanged local state when the server copy changed, keeping a .bak', () async {
    final seeded = env.api.seed('42', stateFileA, stateBytes(1));
    await env.service.pullStates(env.game, env.romPath);
    env.api.touch(seeded.id, stateBytes(2));

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 1);
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(2));
    expect(env.stateFile('$stateFileA.bak').readAsBytesSync(), stateBytes(1));
  });

  test('does not replace a local state when its .bak cannot be made', () async {
    final seeded = env.api.seed('42', stateFileA, stateBytes(1));
    await env.service.pullStates(env.game, env.romPath);
    env.api.touch(seeded.id, stateBytes(2));
    // A directory where the .bak copy goes makes backupSave fail (silently).
    Directory(env.stateFile('$stateFileA.bak').path).createSync();

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 0);
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(1),
        reason: 'no backup, no replace');
    expect(env.stateFile('$stateFileA.freegosy_tmp').existsSync(), isFalse,
        reason: 'a failed write must not leave its temp file behind');
  });

  test('leaves a locally changed state alone when the server copy did not change', () async {
    env.api.seed('42', stateFileA, stateBytes(1));
    await env.service.pullStates(env.game, env.romPath);
    await env.writeState(stateFileA, stateBytes(3));
    env.api.calls.clear();

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 0);
    expect(result.conflicts, isEmpty);
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(3));
    expect(env.api.calls, ['list']);
  });

  test('reports a conflict when both sides changed, touches nothing, and keeps reporting it', () async {
    final seeded = env.api.seed('42', stateFileA, stateBytes(1));
    await env.service.pullStates(env.game, env.romPath);
    await env.writeState(stateFileA, stateBytes(3));
    env.api.touch(seeded.id, stateBytes(2));
    env.api.calls.clear();

    final first = await env.service.pullStates(env.game, env.romPath);

    expect(first.downloaded, 0);
    expect(first.conflicts, hasLength(1));
    expect(first.conflicts.single.fileName, stateFileA);
    expect(first.conflicts.single.cloudStateId, seeded.id);
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(3));
    expect(env.api.bytesOf(seeded.id), stateBytes(2));

    env.api.calls.clear();
    final second = await env.service.pullStates(env.game, env.romPath);

    expect(second.conflicts, hasLength(1), reason: 'flagged conflicts stay open until resolved');
    expect(env.api.calls, ['list'], reason: 're-reporting must not re-download');
  });

  test('first contact with identical bytes links the state without a conflict', () async {
    await env.writeState(stateFileA, stateBytes(1));
    env.api.seed('42', stateFileA, stateBytes(1));

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 0);
    expect(result.conflicts, isEmpty);
  });

  test('reports a state RomM only re-stamped (identical bytes) as up to date, not downloaded', () async {
    await env.writeState(stateFileA, stateBytes(1));
    await env.service.pushStates(env.game, env.romPath); // POST: state id 1
    env.api.touch(1, stateBytes(1)); // updated_at moves, the bytes do not

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloadedFiles, isEmpty);
    expect(result.upToDateFiles, {stateFileA});
    expect(result.currentFiles, {stateFileA});
  });

  test('reports a state linked on first contact (identical bytes) as up to date', () async {
    await env.writeState(stateFileA, stateBytes(1));
    env.api.seed('42', stateFileA, stateBytes(1));

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.upToDateFiles, {stateFileA});
    expect(StateSyncResult.none.upToDateFiles, isEmpty);
  });

  test('a conflict or a download is not reported as up to date', () async {
    await env.writeState(stateFileA, stateBytes(1));
    env.api.seed('42', stateFileA, stateBytes(2)); // first contact, different bytes
    env.api.seed('42', stateFileB, stateBytes(3)); // missing locally

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.upToDateFiles, isEmpty);
    expect(result.downloadedFiles, {stateFileB});
    expect(result.currentFiles, {stateFileB});
  });

  test('first contact with different bytes is a conflict', () async {
    await env.writeState(stateFileA, stateBytes(1));
    env.api.seed('42', stateFileA, stateBytes(2));

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 0);
    expect(result.conflicts, hasLength(1));
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(1));

    env.api.calls.clear();
    final second = await env.service.pullStates(env.game, env.romPath);

    expect(second.conflicts, hasLength(1), reason: 'a first-contact conflict stays open until resolved');
    expect(env.api.calls, ['list'], reason: 're-reporting must not re-download');
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(1));
  });

  test('a failing server list is swallowed and reported as nothing done', () async {
    env.api.failList = true;

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 0);
    expect(result.conflicts, isEmpty);
  });

  test('a second concurrent pull for the same game does nothing while the first is running', () async {
    env.api.seed('42', stateFileA, stateBytes(1));
    env.api.listGate = Completer<void>();

    final first = env.service.pullStates(env.game, env.romPath);
    // Let it reach the held list call (setup does real file I/O first).
    for (var i = 0; i < 200 && !env.api.calls.contains('list'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(env.api.calls, ['list'], reason: 'the first pull must be holding the list call');

    // Without the guard this call would queue behind the held list call, so
    // bound it: the guarded call returns at once.
    final second = await env.service
        .pullStates(env.game, env.romPath)
        .timeout(const Duration(seconds: 2));

    expect(second.downloaded, 0);
    expect(second.conflicts, isEmpty);
    expect(env.api.calls, ['list'], reason: 'only the first pull may talk to the server');

    env.api.listGate!.complete();
    final firstResult = await first;

    expect(firstResult.downloaded, 1);
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(1));
  });

  test('the in-flight guard is released after a pull fails', () async {
    env.api.failList = true;
    final failed = await env.service.pullStates(env.game, env.romPath);
    expect(failed.downloaded, 0);

    env.api.failList = false;
    env.api.seed('42', stateFileA, stateBytes(1));
    final retry = await env.service.pullStates(env.game, env.romPath);

    expect(retry.downloaded, 1, reason: 'a failed pull must not lock the game out of later pulls');
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(1));
  });

  test('a list call that never answers times out fast and does not lock the game', () async {
    final slow = await StateSyncTestEnv.create(listTimeout: const Duration(milliseconds: 50));
    addTearDown(slow.dispose);
    slow.api.listGate = Completer<void>(); // never completed: an unreachable server

    // Without the list timeout this would hang; the outer bound makes that a
    // fast failure instead of a stuck test.
    final result = await slow.service
        .pullStates(slow.game, slow.romPath)
        .timeout(const Duration(seconds: 2));

    expect(result.downloaded, 0);
    expect(result.conflicts, isEmpty);

    slow.api.listGate = null;
    slow.api.seed('42', stateFileA, stateBytes(1));
    final retry = await slow.service
        .pullStates(slow.game, slow.romPath)
        .timeout(const Duration(seconds: 2));

    expect(retry.downloaded, 1, reason: 'the timed-out pull must release the game');
    expect(slow.stateFile(stateFileA).readAsBytesSync(), stateBytes(1));
  });

  test('reports skipped when the game cannot be identified', () async {
    env.api.seed('42', stateFileA, stateBytes(1));

    final result = await env.service
        .pullStates(env.game, p.join(env.base.path, 'Unknown Game.iso'));

    expect(result.skipped, isTrue);
    expect(result.downloaded, 0);
    expect(env.api.calls, isEmpty);
  });

  test('reports skipped while the toggle is off', () async {
    final disabled = await StateSyncTestEnv.create(enabled: false);
    addTearDown(disabled.dispose);

    final result = await disabled.service.pullStates(disabled.game, disabled.romPath);

    expect(result.skipped, isTrue);
  });

  group('a failing download', () {
    const stateFileC = 'SCUS-97113 (A1B2C3D4).02.p2s';
    bool isGet(String call) => call.startsWith('GET ');

    test('stops the pull at the first failed download and frees the game', () async {
      env.api.seed('42', stateFileA, stateBytes(1));
      env.api.seed('42', stateFileB, stateBytes(2));
      env.api.seed('42', stateFileC, stateBytes(3));
      env.api.failDownloads = true;

      final result = await env.service.pullStates(env.game, env.romPath);

      expect(env.api.calls.where(isGet), hasLength(1),
          reason: 'a stalling server must not be tried again for every remaining state');
      expect(result.downloaded, 0);
      expect(result.conflicts, isEmpty);
      expect(result.busy, isFalse);
      expect(result.skipped, isFalse);

      env.api.failDownloads = false;
      final retry = await env.service.pullStates(env.game, env.romPath);

      expect(retry.downloaded, 3, reason: 'the failed pull must not lock the game');
    });

    test('keeps what was already downloaded and skips the rest', () async {
      final first = env.api.seed('42', stateFileA, stateBytes(1));
      final second = env.api.seed('42', stateFileB, stateBytes(2));
      env.api.seed('42', stateFileC, stateBytes(3));
      env.api.downloadGates[second.id] = Completer<void>();

      final pull = env.service.pullStates(env.game, env.romPath);
      for (var i = 0; i < 400 && !env.api.calls.contains('GET ${second.id}'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(env.api.calls, ['list', 'GET ${first.id}', 'GET ${second.id}']);
      env.api.failDownloads = true; // the second download stalls out
      env.api.downloadGates[second.id]!.complete();
      final result = await pull;

      expect(result.downloaded, 1);
      expect(env.api.calls.where(isGet), hasLength(2), reason: 'the third state is never tried');
      expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(1));
      expect(env.stateFile(stateFileB).existsSync(), isFalse);
      expect(env.stateFile(stateFileC).existsSync(), isFalse);
    });

    test('a state that vanished from the server does not stop the pull', () async {
      env.api.seed('42', stateFileA, stateBytes(1));
      final gone = env.api.seed('42', stateFileB, stateBytes(2));
      env.api.seed('42', stateFileC, stateBytes(3));
      env.api.vanishOnDownload.add(gone.id);

      final result = await env.service.pullStates(env.game, env.romPath);

      expect(env.api.calls.where(isGet), hasLength(3));
      expect(result.downloaded, 2);
      expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(1));
      expect(env.stateFile(stateFileB).existsSync(), isFalse);
      expect(env.stateFile(stateFileC).readAsBytesSync(), stateBytes(3));
    });
  });

  test('a normal pull is not skipped, with or without anything to do', () async {
    expect((await env.service.pullStates(env.game, env.romPath)).skipped, isFalse);

    env.api.seed('42', stateFileA, stateBytes(1));
    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 1);
    expect(result.skipped, isFalse);
  });

  test('a strategy resolver that throws never makes a pull throw', () async {
    final broken = StateSyncService(env.api, env.pcsx2.prefs,
        (game, {emulatorId}) => throw StateError('no strategy'));

    final result = await broken.pullStates(env.game, env.romPath);

    expect(result.skipped, isTrue);
    expect(result.downloaded, 0);
  });
}
