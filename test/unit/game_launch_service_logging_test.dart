import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/game_launch_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/save/backup_repository.dart';
import 'package:freegosy/core/save/backup_service.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/save/state_sync_service.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_romm_states_api.dart';
import '../helpers/pcsx2_test_env.dart';

/// Captures the debugPrints of the current test that start with [tag], in order
/// (other components log during a launch too).
List<String> _captureLogs(String tag) {
  final logs = <String>[];
  final old = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && message.startsWith(tag)) logs.add(message);
  };
  addTearDown(() => debugPrint = old);
  return logs;
}

void main() {
  late Directory base;
  late Pcsx2TestEnv env;
  late String romPath;
  final game = Game(id: '42', name: 'Ico (SCUS-97113)', platformSlug: 'ps2', fileSize: 0);

  GameLaunchService buildService({StateSyncService? stateSync}) {
    final registry = StrategyRegistry(env.directoryService, env.prefs);
    final rommService = RommService(
      RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', apiKey: 'k'),
      skipConnectivityCheck: true,
    );
    return GameLaunchService(
      directoryService: env.directoryService,
      strategyRegistry: registry,
      saveSyncService: SaveSyncService(rommService, env.directoryService, registry, env.prefs),
      backupService: BackupService(),
      backupRepository: BackupRepository(),
      prefs: env.prefs,
      stateSyncService: stateSync,
    );
  }

  GameSession session() => GameSession(
        process: null,
        sessionStart: DateTime(2026, 1, 1),
        emulatorId: 'pcsx2',
        activityTrackerFuture: Future.value(null),
      );

  setUp(() async {
    base = await Directory.systemTemp.createTemp('launch_logging');
    env = await Pcsx2TestEnv.create(base);
    romPath = p.join(base.path, 'Ico (SCUS-97113).iso');
  });

  tearDown(() => base.delete(recursive: true));

  group('pushStatesAfterExit logs', () {
    test('that it was skipped when there is no state sync service', () async {
      final logs = _captureLogs('[StateSync]');

      final conflicts = await buildService().pushStatesAfterExit(session(), game, romPath);

      expect(conflicts, 0);
      expect(logs, ['[StateSync] post-exit push skipped: state sync service not available']);
    });

    test('that it ran, before the service reports what it did', () async {
      final stateSync = StateSyncService(FakeRommStatesApi(), env.prefs, (g, {emulatorId, coreOverride}) => null);
      final logs = _captureLogs('[StateSync]');

      await buildService(stateSync: stateSync).pushStatesAfterExit(session(), game, romPath);

      expect(logs.first, '[StateSync] post-exit push for Ico (SCUS-97113) (emulator pcsx2)');
      expect(logs, hasLength(2), reason: 'the service adds its own skip reason: $logs');
    });
  });
}
