import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/save_strategy.dart';
import 'package:freegosy/core/save/state_sync_capable.dart';
import 'package:freegosy/core/save/state_sync_service.dart';

import '../helpers/state_sync_test_env.dart';

/// A strategy whose matcher accepts every file name, so the only thing between
/// a server-controlled name and the local file system is StateSyncService's own
/// name check (the real strategies also filter names, which would mask it).
class _PermissiveStrategy extends SaveStrategy with StateSyncCapable {
  _PermissiveStrategy(this.statesDir);

  final String statesDir;

  @override
  String get strategyId => 'permissive';

  @override
  Future<String?> getSaveDir(Game game, String romPath) async => null;

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
          {DateTime? sessionStart, String syncMode = 'both'}) async =>
      [];

  @override
  Future<bool> restoreSave(
          Game game, String destPath, Uint8List data, String filename) async =>
      false;

  @override
  Future<String> stateDirectory(Game game, String romPath) async => statesDir;

  @override
  Future<bool Function(String fileName)?> stateFileMatcher(
          Game game, String romPath) async =>
      (_) => true;
}

Set<String> _allFiles(Directory dir) => {
      for (final e in dir.listSync(recursive: true))
        if (e is File) e.path,
    };

void main() {
  late StateSyncTestEnv env;
  late StateSyncService service;

  setUp(() async {
    env = await StateSyncTestEnv.create();
    await env.pcsx2.prefs.setBool(StateSyncService.enabledKey('permissive'), true);
    service = StateSyncService(env.api, env.pcsx2.prefs,
        (game, {emulatorId, coreOverride}) => _PermissiveStrategy(env.statesDir));
  });
  tearDown(() => env.dispose());

  for (final name in [r'..\evil.p2s', '../evil.p2s', '.', '..']) {
    test('never downloads or writes a server state named "$name"', () async {
      await Directory(env.statesDir).create(recursive: true);
      env.api.seed('42', name, stateBytes(1));
      final before = _allFiles(env.base);

      final result = await service.pullStates(env.game, env.romPath);

      expect(result.downloaded, 0);
      expect(result.conflicts, isEmpty);
      expect(env.api.calls, ['list'], reason: 'an unsafe name must be skipped before any download');
      expect(_allFiles(env.base), before, reason: 'nothing may be written anywhere');
    });
  }
}
