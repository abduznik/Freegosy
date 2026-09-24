import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/state_sync_test_env.dart';

/// Mockup PCSX2 states in test/fixtures/pcsx2_states (see generate.py there):
/// two real zip-shaped states and three damaged ones.
List<int> fixture(String name) =>
    File(p.join('test', 'fixtures', 'pcsx2_states', name)).readAsBytesSync();

const damaged = {
  'truncated.p2s': 'a write cut off halfway (zip header, no end record)',
  'zeroed.p2s': 'a preallocated file that was never filled in',
  'garbage.p2s': 'not a state at all',
};

void main() {
  late StateSyncTestEnv env;

  setUp(() async => env = await StateSyncTestEnv.create());
  tearDown(() => env.dispose());

  group('Pcsx2SaveStrategy.looksLikeValidState on the mockups', () {
    test('accepts the valid mockups', () {
      for (final name in ['valid.p2s', 'valid_other.p2s']) {
        expect(env.pcsx2.strategy.looksLikeValidState(Uint8List.fromList(fixture(name))),
            isTrue, reason: name);
      }
    });

    for (final entry in damaged.entries) {
      test('rejects ${entry.key} (${entry.value})', () {
        expect(
            env.pcsx2.strategy.looksLikeValidState(Uint8List.fromList(fixture(entry.key))),
            isFalse);
      });
    }
  });

  group('push', () {
    test('uploads a valid mockup state', () async {
      await env.writeState(stateFileA, fixture('valid.p2s'));

      final result = await env.service.pushStates(env.game, env.romPath);

      expect(result.uploaded, 1);
      expect(env.api.calls, ['list', 'POST $stateFileA']);
    });

    for (final entry in damaged.entries) {
      test('never uploads ${entry.key} as a new state', () async {
        await env.writeState(stateFileA, fixture(entry.key));

        final result = await env.service.pushStates(env.game, env.romPath);

        expect(result.uploaded, 0);
        expect(result.conflicts, isEmpty);
        expect(env.api.calls.where((c) => c.startsWith('POST') || c.startsWith('PUT')), isEmpty);
        expect(env.api.count, 0);
      });

      test('after exit, ${entry.key} does not overwrite the good server copy', () async {
        final sessionStart = DateTime.now().subtract(const Duration(minutes: 5));
        await env.writeState(stateFileA, fixture('valid.p2s'));
        await env.service.pushStates(env.game, env.romPath);
        final stateId = (await env.api.listStates('42')).single.id;

        // The emulator's write during the session went wrong.
        await env.writeState(stateFileA, fixture(entry.key));
        env.api.calls.clear();
        final result = await env.service.pushStates(env.game, env.romPath,
            sessionStart: sessionStart);

        expect(result.uploaded, 0);
        expect(env.api.calls.where((c) => c.startsWith('POST') || c.startsWith('PUT')), isEmpty);
        expect(env.api.bytesOf(stateId), fixture('valid.p2s'),
            reason: 'the server keeps the last good state');
      });
    }

    test('a damaged state does not stop the valid ones in the same push', () async {
      await env.writeState(stateFileA, fixture('truncated.p2s'));
      await env.writeState(stateFileB, fixture('valid.p2s'));

      final result = await env.service.pushStates(env.game, env.romPath);

      expect(result.uploaded, 1);
      expect(env.api.calls, ['list', 'POST $stateFileB']);
    });

    test('a damaged state is uploaded once it is valid again', () async {
      await env.writeState(stateFileA, fixture('zeroed.p2s'));
      await env.service.pushStates(env.game, env.romPath);
      await env.writeState(stateFileA, fixture('valid.p2s'));
      env.api.calls.clear();

      final result = await env.service.pushStates(env.game, env.romPath);

      expect(result.uploaded, 1);
      expect(env.api.calls, ['list', 'POST $stateFileA']);
    });
  });

  test('pull does not replace a local state with a truncated server copy', () async {
    await env.writeState(stateFileA, fixture('valid.p2s'));
    await env.service.pushStates(env.game, env.romPath);
    final stateId = (await env.api.listStates('42')).single.id;
    env.api.touch(stateId, fixture('truncated.p2s')); // another machine's upload broke

    final result = await env.service.pullStates(env.game, env.romPath);

    expect(result.downloaded, 0);
    expect(env.stateFile(stateFileA).readAsBytesSync(), fixture('valid.p2s'));
  });

  test('"Use Local Version" refuses a truncated local state', () async {
    final seeded = env.api.seed('42', stateFileA, fixture('valid.p2s'));
    await env.service.pullStates(env.game, env.romPath);
    await env.writeState(stateFileA, fixture('valid_other.p2s'));
    env.api.touch(seeded.id, stateBytes(2)); // changed on another machine too
    final conflict = (await env.service.pullStates(env.game, env.romPath)).conflicts.single;

    await env.writeState(stateFileA, fixture('truncated.p2s'));
    final ok = await env.service.resolveConflict(conflict, choice: 'local');

    expect(ok, isFalse);
    expect(env.api.bytesOf(seeded.id), stateBytes(2));
  });
}
