import 'package:flutter_test/flutter_test.dart';
import '../helpers/state_sync_test_env.dart';

void main() {
  late StateSyncTestEnv env;
  setUp(() async => env = await StateSyncTestEnv.create());
  tearDown(() => env.dispose());

  test('the priority state is downloaded first', () async {
    final a = env.api.seed('42', stateFileA, stateBytes(1));
    final b = env.api.seed('42', stateFileB, stateBytes(2));
    await env.service.pullStates(env.game, env.romPath, priority: stateFileB);
    final gets = env.api.calls.where((c) => c.startsWith('GET ')).toList();
    expect(gets, ['GET ${b.id}', 'GET ${a.id}']);
  });

  test('a failing download of another slot does not block the priority one', () async {
    env.api.seed('42', stateFileA, stateBytes(1)); // listed first by the server
    final b = env.api.seed('42', stateFileB, stateBytes(2));
    var first = true;
    env.api.failDownloadsAfterFirst = () {
      final failThis = !first;
      first = false;
      return failThis; // the first GET succeeds, every later one fails
    };
    final result =
        await env.service.pullStates(env.game, env.romPath, priority: stateFileB);
    expect(result.downloaded, 1);
    expect(env.stateFile(stateFileB).readAsBytesSync(), stateBytes(2));
    expect(env.api.calls.where((c) => c.startsWith('GET ')).first, 'GET ${b.id}');
  });

  test('without priority the server order is kept', () async {
    final a = env.api.seed('42', stateFileA, stateBytes(1));
    final b = env.api.seed('42', stateFileB, stateBytes(2));
    await env.service.pullStates(env.game, env.romPath);
    expect(env.api.calls.where((c) => c.startsWith('GET ')).toList(), ['GET ${a.id}', 'GET ${b.id}']);
  });
}
