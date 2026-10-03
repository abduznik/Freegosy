import 'dart:async';

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
    await disabled.writeState(stateFileA, stateBytes(1));

    final result = await disabled.service.pushStates(disabled.game, disabled.romPath);

    expect(result.uploaded, 0);
    expect(disabled.api.calls, isEmpty);
  });

  test('uploads a new state with POST and does not re-upload it while unchanged', () async {
    await env.writeState(stateFileA, stateBytes(1));

    final first = await env.service.pushStates(env.game, env.romPath);

    expect(first.uploaded, 1);
    expect(env.api.calls, ['list', 'POST $stateFileA']);

    env.api.calls.clear();
    final second = await env.service.pushStates(env.game, env.romPath);

    expect(second.uploaded, 0);
    expect(env.api.calls, ['list'], reason: 'unchanged hash: no upload');
  });

  test('a modified state is updated in place with PUT', () async {
    await env.writeState(stateFileA, stateBytes(1));
    await env.service.pushStates(env.game, env.romPath);
    await env.writeState(stateFileA, stateBytes(2));
    env.api.calls.clear();

    final result = await env.service.pushStates(env.game, env.romPath);

    expect(result.uploaded, 1);
    expect(env.api.calls.last, startsWith('PUT '));
    expect(env.api.count, 1, reason: 'updated, not duplicated');
  });

  test('with a sessionStart, only files modified in the session are pushed', () async {
    final now = DateTime.now();
    await env.writeState(stateFileA, stateBytes(1), modified: now.subtract(const Duration(days: 1)));
    await env.writeState(stateFileB, stateBytes(2), modified: now);

    final result = await env.service.pushStates(env.game, env.romPath,
        sessionStart: now.subtract(const Duration(minutes: 5)));

    expect(result.uploaded, 1);
    expect(env.api.calls, ['list', 'POST $stateFileB']);
  });

  test('skips files too small to be a real state', () async {
    await env.writeState(stateFileA, [0x50, 0x4B, 3, 4]);

    final result = await env.service.pushStates(env.game, env.romPath);

    expect(result.uploaded, 0);
    expect(env.api.calls, isEmpty);
  });

  test('ignores .backup, .bak and other games\' states', () async {
    await env.writeState('$stateFileA.backup', stateBytes(1));
    await env.writeState('$stateFileA.bak', stateBytes(1));
    await env.writeState('SLUS-20312 (A1B2C3D4).01.p2s', stateBytes(1));

    final result = await env.service.pushStates(env.game, env.romPath);

    expect(result.uploaded, 0);
    expect(env.api.calls, isEmpty);
  });

  test('flags a conflict instead of overwriting when the server copy changed too', () async {
    await env.writeState(stateFileA, stateBytes(1));
    await env.service.pushStates(env.game, env.romPath);
    final stateId = (await env.api.listStates('42')).single.id;
    env.api.touch(stateId, stateBytes(2)); // another machine pushed
    await env.writeState(stateFileA, stateBytes(3));
    env.api.calls.clear();

    final result = await env.service.pushStates(env.game, env.romPath);

    expect(result.uploaded, 0);
    expect(result.conflicts, hasLength(1));
    expect(result.conflicts.single.fileName, stateFileA);
    expect(env.api.calls, ['list'], reason: 'no PUT: the server copy must survive');
    expect(env.api.bytesOf(stateId), stateBytes(2));

    env.api.calls.clear();
    final again = await env.service.pushStates(env.game, env.romPath);

    expect(again.conflicts, hasLength(1), reason: 'stays flagged until resolved');
    expect(env.api.calls, ['list']);
  });

  test('a flagged conflict is not dropped when the local file goes back to its last-synced bytes', () async {
    await env.writeState(stateFileA, stateBytes(1));
    await env.service.pushStates(env.game, env.romPath);
    final stateId = (await env.api.listStates('42')).single.id;
    env.api.touch(stateId, stateBytes(2)); // another machine pushed
    await env.writeState(stateFileA, stateBytes(3));
    final flagged = await env.service.pushStates(env.game, env.romPath);
    expect(flagged.conflicts, hasLength(1));

    await env.writeState(stateFileA, stateBytes(1)); // back to the last-synced bytes
    env.api.calls.clear();
    final again = await env.service.pushStates(env.game, env.romPath);

    expect(again.uploaded, 0);
    expect(again.conflicts, hasLength(1), reason: 'a flagged conflict only clears through resolution');
    expect(env.api.calls, ['list']);
  });

  test('a same-named server state we never synced with is a conflict, not an overwrite', () async {
    await env.writeState(stateFileA, stateBytes(1));
    final seeded = env.api.seed('42', stateFileA, stateBytes(2));

    final result = await env.service.pushStates(env.game, env.romPath);

    expect(result.uploaded, 0);
    expect(result.conflicts, hasLength(1));
    expect(env.api.bytesOf(seeded.id), stateBytes(2));
  });

  test('a same-named server state with identical bytes is linked without an upload', () async {
    await env.writeState(stateFileA, stateBytes(1));
    env.api.seed('42', stateFileA, stateBytes(1));

    final result = await env.service.pushStates(env.game, env.romPath);

    expect(result.uploaded, 0);
    expect(result.conflicts, isEmpty);
    expect(env.api.calls.where((c) => c.startsWith('PUT') || c.startsWith('POST')), isEmpty);
  });

  test('a state deleted on the server is re-created with POST (dead link)', () async {
    await env.writeState(stateFileA, stateBytes(1));
    await env.service.pushStates(env.game, env.romPath);
    final stateId = (await env.api.listStates('42')).single.id;
    env.api.remove(stateId);
    await env.writeState(stateFileA, stateBytes(2));
    env.api.calls.clear();

    final result = await env.service.pushStates(env.game, env.romPath);

    expect(result.uploaded, 1);
    expect(env.api.calls, ['list', 'POST $stateFileA']);
  });

  group('a flagged conflict whose server copy disappeared', () {
    // Pinned behaviour: with no server copy there is nothing to conflict with,
    // so the local state is uploaded again and the flag clears. Nothing on the
    // server is overwritten and the local file is never touched.
    test('is uploaded again from the local bytes and the flag clears', () async {
      await env.writeState(stateFileA, stateBytes(1));
      await env.service.pushStates(env.game, env.romPath);
      final stateId = (await env.api.listStates('42')).single.id;
      env.api.touch(stateId, stateBytes(2)); // another machine pushed
      await env.writeState(stateFileA, stateBytes(3));
      final flagged = await env.service.pushStates(env.game, env.romPath);
      expect(flagged.conflicts, hasLength(1), reason: 'setup: both sides changed');
      env.api.remove(stateId);
      env.api.calls.clear();

      final result = await env.service.pushStates(env.game, env.romPath);

      expect(result.uploaded, 1);
      expect(result.conflicts, isEmpty);
      expect(env.api.calls, ['list', 'POST $stateFileA']);
      final newId = (await env.api.listStates('42')).single.id;
      expect(env.api.bytesOf(newId), stateBytes(3), reason: 'the server now holds the local state');
      expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(3));

      env.api.calls.clear();
      final push = await env.service.pushStates(env.game, env.romPath);
      final pull = await env.service.pullStates(env.game, env.romPath);

      expect(push.uploaded, 0);
      expect(push.conflicts, isEmpty);
      expect(pull.conflicts, isEmpty);
      expect(pull.downloaded, 0);
      expect(env.api.calls, ['list', 'list'], reason: 'no upload, no download: the slot is clean');
    });

    test('also applies to a first-contact conflict', () async {
      await env.writeState(stateFileA, stateBytes(1));
      final seeded = env.api.seed('42', stateFileA, stateBytes(2));
      final flagged = await env.service.pushStates(env.game, env.romPath);
      expect(flagged.conflicts, hasLength(1), reason: 'setup: same name, no shared history');
      env.api.remove(seeded.id);
      env.api.calls.clear();

      final result = await env.service.pushStates(env.game, env.romPath);

      expect(result.uploaded, 1);
      expect(result.conflicts, isEmpty);
      expect(env.api.calls, ['list', 'POST $stateFileA']);
      final newId = (await env.api.listStates('42')).single.id;
      expect(env.api.bytesOf(newId), stateBytes(1));

      env.api.calls.clear();
      final push = await env.service.pushStates(env.game, env.romPath);
      final pull = await env.service.pullStates(env.game, env.romPath);

      expect(push.uploaded, 0);
      expect(push.conflicts, isEmpty);
      expect(pull.conflicts, isEmpty);
      expect(env.api.calls, ['list', 'list']);
    });
  });

  test('a PUT that hits a 404 falls back to POST', () async {
    await env.writeState(stateFileA, stateBytes(1));
    await env.service.pushStates(env.game, env.romPath);
    await env.writeState(stateFileA, stateBytes(2));
    env.api.nextUpdateIs404 = true;
    env.api.calls.clear();

    final result = await env.service.pushStates(env.game, env.romPath);

    expect(result.uploaded, 1);
    expect(env.api.calls.last, 'POST $stateFileA');
  });

  test('a failing server list is swallowed', () async {
    await env.writeState(stateFileA, stateBytes(1));
    env.api.failList = true;

    final result = await env.service.pushStates(env.game, env.romPath);

    expect(result.uploaded, 0);
    expect(result.conflicts, isEmpty);
  });

  test('a list call that never answers times out fast and does not lock the game', () async {
    final slow = await StateSyncTestEnv.create(listTimeout: const Duration(milliseconds: 50));
    addTearDown(slow.dispose);
    await slow.writeState(stateFileA, stateBytes(1));
    slow.api.listGate = Completer<void>(); // never completed: an unreachable server

    final result = await slow.service
        .pushStates(slow.game, slow.romPath)
        .timeout(const Duration(seconds: 2));

    expect(result.uploaded, 0);
    expect(result.conflicts, isEmpty);

    slow.api.listGate = null;
    final retry = await slow.service
        .pushStates(slow.game, slow.romPath)
        .timeout(const Duration(seconds: 2));

    expect(retry.uploaded, 1, reason: 'the timed-out push must release the game');
  });

  test('reports skipped when the game cannot be identified', () async {
    await env.writeState(stateFileA, stateBytes(1));

    final result = await env.service
        .pushStates(env.game, p.join(env.base.path, 'Unknown Game.iso'));

    expect(result.skipped, isTrue);
    expect(result.uploaded, 0);
    expect(env.api.calls, isEmpty);
  });

  test('reports skipped while the toggle is off', () async {
    final disabled = await StateSyncTestEnv.create(enabled: false);
    addTearDown(disabled.dispose);

    final result = await disabled.service.pushStates(disabled.game, disabled.romPath);

    expect(result.skipped, isTrue);
  });

  test('a normal push is not skipped, with or without anything to do', () async {
    expect((await env.service.pushStates(env.game, env.romPath)).skipped, isFalse);

    await env.writeState(stateFileA, stateBytes(1));
    final result = await env.service.pushStates(env.game, env.romPath);

    expect(result.uploaded, 1);
    expect(result.skipped, isFalse);
  });

  test('a strategy resolver that throws never makes a push throw', () async {
    await env.writeState(stateFileA, stateBytes(1));
    final broken = StateSyncService(env.api, env.pcsx2.prefs,
        (game, {emulatorId, coreOverride}) => throw StateError('no strategy'));

    final result = await broken.pushStates(env.game, env.romPath);

    expect(result.skipped, isTrue);
    expect(result.uploaded, 0);
  });
}
