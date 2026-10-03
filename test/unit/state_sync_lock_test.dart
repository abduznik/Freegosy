import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/state_sync_service.dart';

import '../helpers/state_sync_test_env.dart';

void main() {
  // The save strategies are shared by every game and hold one game's setup
  // (RetroArch's core): state sync must run under the save lock, set up with
  // the session's core, like save sync does.
  test('state push and pull run under the save lock, with the session\'s core', () async {
    final env = await StateSyncTestEnv.create();
    addTearDown(env.dispose);
    final locked = <String>[];
    final cores = <String?>[];
    final service = StateSyncService(env.api, env.pcsx2.prefs, (game, {emulatorId, coreOverride}) {
      cores.add(coreOverride);
      return env.pcsx2.strategy;
    }, exclusive: <T>(Future<T> Function() body) {
      locked.add('run');
      return body();
    });

    await service.pushStates(env.game, env.romPath, emulatorId: 'pcsx2', coreOverride: 'x_libretro');
    await service.pullStates(env.game, env.romPath, emulatorId: 'pcsx2', coreOverride: 'x_libretro');
    expect(locked, ['run', 'run']);
    expect(cores, everyElement('x_libretro'));
    expect(cores, isNotEmpty);
  });
}
