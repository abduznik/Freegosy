import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/state_sync_service.dart';

import '../helpers/state_sync_test_env.dart';

void main() {
  late StateSyncTestEnv env;
  late StateConflict conflict;
  late int stateId;

  /// Local = seed 3, server = seed 2, both changed since a synced seed 1.
  setUp(() async {
    env = await StateSyncTestEnv.create();
    final seeded = env.api.seed('42', stateFileA, stateBytes(1));
    stateId = seeded.id;
    await env.service.pullStates(env.game, env.romPath);
    await env.writeState(stateFileA, stateBytes(3));
    env.api.touch(stateId, stateBytes(2));
    conflict = (await env.service.pullStates(env.game, env.romPath)).conflicts.single;
  });

  tearDown(() => env.dispose());

  test('choosing local uploads the local bytes and clears the conflict', () async {
    final ok = await env.service.resolveConflict(conflict, choice: 'local');

    expect(ok, isTrue);
    expect(env.api.bytesOf(stateId), stateBytes(3));
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(3));

    env.api.calls.clear();
    expect((await env.service.pullStates(env.game, env.romPath)).conflicts, isEmpty);
    expect((await env.service.pushStates(env.game, env.romPath)).conflicts, isEmpty);
    expect(env.api.calls.where((c) => c.startsWith('PUT') || c.startsWith('POST')), isEmpty,
        reason: 'the record was updated, so nothing is pending');
  });

  test('choosing cloud replaces the local state, keeps a .bak of it, and clears the conflict', () async {
    final ok = await env.service.resolveConflict(conflict, choice: 'cloud');

    expect(ok, isTrue);
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(2));
    expect(env.stateFile('$stateFileA.bak').readAsBytesSync(), stateBytes(3));

    env.api.calls.clear();
    expect((await env.service.pullStates(env.game, env.romPath)).conflicts, isEmpty);
    expect((await env.service.pushStates(env.game, env.romPath)).conflicts, isEmpty);
  });

  test('choosing local re-creates the state if it vanished from the server meanwhile', () async {
    env.api.remove(stateId);

    final ok = await env.service.resolveConflict(conflict, choice: 'local');

    expect(ok, isTrue);
    expect(env.api.calls.last, 'POST $stateFileA');
  });

  test('an unknown choice changes nothing and returns false', () async {
    final ok = await env.service.resolveConflict(conflict, choice: 'nope');

    expect(ok, isFalse);
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(3));
    expect(env.api.bytesOf(stateId), stateBytes(2));
  });

  test('choosing cloud after the server copy vanished returns false and keeps the local file', () async {
    env.api.remove(stateId);

    final ok = await env.service.resolveConflict(conflict, choice: 'cloud');

    expect(ok, isFalse);
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(3));
  });

  test('choosing local with a truncated local file returns false and leaves the server copy untouched', () async {
    await env.writeState(stateFileA, List<int>.filled(10, 7));
    env.api.calls.clear();

    final ok = await env.service.resolveConflict(conflict, choice: 'local');

    expect(ok, isFalse);
    expect(env.api.bytesOf(stateId), stateBytes(2));
    expect(env.api.calls.where((c) => c.startsWith('PUT') || c.startsWith('POST')), isEmpty,
        reason: 'a truncated local state must never be uploaded over the server copy');
  });

  test('a failed resolve keeps the conflict open', () async {
    await env.writeState(stateFileA, List<int>.filled(10, 7));

    expect(await env.service.resolveConflict(conflict, choice: 'local'), isFalse);

    expect((await env.service.pullStates(env.game, env.romPath)).conflicts, hasLength(1));
  });

  test('choosing cloud when the .bak cannot be made leaves the local state untouched and the conflict open', () async {
    // A directory where the .bak copy goes makes backupSave fail (silently).
    Directory(env.stateFile('$stateFileA.bak').path).createSync();

    final ok = await env.service.resolveConflict(conflict, choice: 'cloud');

    expect(ok, isFalse);
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(3),
        reason: 'no backup, no replace');
    expect(env.stateFile('$stateFileA.freegosy_tmp').existsSync(), isFalse,
        reason: 'a failed write must not leave its temp file behind');

    final again = await env.service.pullStates(env.game, env.romPath);
    expect(again.conflicts, hasLength(1), reason: 'the conflict stays open');
    expect(again.downloaded, 0);
  });

  test('returns false when state sync is no longer available', () async {
    final disabled = await StateSyncTestEnv.create(enabled: false);
    addTearDown(disabled.dispose);

    expect(await disabled.service.resolveConflict(conflict, choice: 'local'), isFalse);
  });

  test('returns false instead of throwing when the strategy resolver throws', () async {
    final broken = StateSyncService(env.api, env.pcsx2.prefs,
        (game, {emulatorId, coreOverride}) => throw StateError('no strategy'));

    expect(await broken.resolveConflict(conflict, choice: 'local'), isFalse);
    expect(env.stateFile(stateFileA).readAsBytesSync(), stateBytes(3));
  });
}
