import 'package:flutter_test/flutter_test.dart';
import '../helpers/p2s_builder.dart';
import '../helpers/state_sync_test_env.dart';

void main() {
  late StateSyncTestEnv env;
  setUp(() async => env = await StateSyncTestEnv.create());
  tearDown(() => env.dispose());

  test('a new upload is tagged with the emulator id and carries the screenshot', () async {
    await env.writeState(stateFileA, buildP2s(screenshot: [0x89, 0x50, 1, 2]));
    final result = await env.service.pushStates(env.game, env.romPath, emulatorId: 'pcsx2');
    expect(result.uploaded, 1);
    expect(env.api.emulatorOf(1), 'pcsx2');
    expect(env.api.screenshotOf(1), [0x89, 0x50, 1, 2]);
  });

  test('without an emulator id the strategy id is used', () async {
    await env.writeState(stateFileA, buildP2s());
    await env.service.pushStates(env.game, env.romPath);
    expect(env.api.emulatorOf(1), 'pcsx2');
  });

  test('an update (PUT) refreshes the screenshot', () async {
    await env.writeState(stateFileA, buildP2s(screenshot: [1]));
    await env.service.pushStates(env.game, env.romPath);
    await env.writeState(stateFileA, buildP2s(screenshot: [2], version: 'v2.8.3'));
    await env.service.pushStates(env.game, env.romPath);
    expect(env.api.calls, contains('PUT 1'));
    expect(env.api.screenshotOf(1), [2]);
  });

  test('a state without a readable screenshot still uploads', () async {
    await env.writeState(stateFileA, stateBytes(3)); // zip magic but not a real zip
    final result = await env.service.pushStates(env.game, env.romPath);
    expect(result.uploaded, 1);
    expect(env.api.screenshotOf(1), isNull);
  });

  test('keep-local conflict resolution also sends the screenshot', () async {
    final seeded = env.api.seed('42', stateFileA, stateBytes(1));
    await env.writeState(stateFileA, buildP2s(screenshot: [7]));
    final push = await env.service.pushStates(env.game, env.romPath);
    expect(push.conflicts, hasLength(1));
    expect(await env.service.resolveConflict(push.conflicts.single, choice: 'local'), isTrue);
    expect(env.api.screenshotOf(seeded.id), [7]);
  });

}
