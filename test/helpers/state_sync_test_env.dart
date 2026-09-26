import 'dart:io';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/state_sync_service.dart';
import 'package:path/path.dart' as p;

import 'fake_romm_states_api.dart';
import 'pcsx2_test_env.dart';

const stateFileA = 'SCUS-97113 (A1B2C3D4).01.p2s';
const stateFileB = 'SCUS-97113 (A1B2C3D4).resume.p2s';

/// Bytes that pass PCSX2's state validation: a zip header, a payload larger
/// than StateSyncService.minValidStateBytes and a zip end record. Different
/// [seed]s differ. For real zip-shaped states see test/fixtures/pcsx2_states.
List<int> stateBytes(int seed) =>
    [0x50, 0x4B, 3, 4, ...List.filled(200, seed), 0x50, 0x4B, 5, 6, ...List.filled(18, 0)];

/// A portable PCSX2 install, a fake RomM states API and a StateSyncService
/// wired to both, for the game "Ico (SCUS-97113)" (RomM rom id `42`).
class StateSyncTestEnv {
  StateSyncTestEnv._(this.base, this.pcsx2, this.api, this.service, this.game, this.romPath);

  final Directory base;
  final Pcsx2TestEnv pcsx2;
  final FakeRommStatesApi api;
  final StateSyncService service;
  final Game game;
  final String romPath;

  static Future<StateSyncTestEnv> create({
    bool enabled = true,
    Duration listTimeout = StateSyncService.defaultListTimeout,
  }) async {
    final base = await Directory.systemTemp.createTemp('state_sync');
    final pcsx2 = await Pcsx2TestEnv.create(base);
    if (enabled) {
      await pcsx2.prefs.setBool(StateSyncService.enabledKey('pcsx2'), true);
    }
    final api = FakeRommStatesApi();
    final service = StateSyncService(api, pcsx2.prefs, (game, {emulatorId}) => pcsx2.strategy,
        listTimeout: listTimeout);
    final game = Game(id: '42', name: 'Ico (SCUS-97113)', platformSlug: 'ps2', fileSize: 0);
    return StateSyncTestEnv._(
        base, pcsx2, api, service, game, p.join(base.path, 'Ico (SCUS-97113).iso'));
  }

  String get statesDir => pcsx2.statesDir;

  File stateFile(String name) => File(p.join(statesDir, name));

  Future<File> writeState(String name, List<int> bytes, {DateTime? modified}) async {
    final file = stateFile(name);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    if (modified != null) await file.setLastModified(modified);
    return file;
  }

  Future<void> dispose() => base.delete(recursive: true);
}
