import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/save_state_info.dart';
import 'package:freegosy/core/save/save_strategy.dart';
import 'package:freegosy/core/save/state_sync_capable.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Implements only the required members, so the mixin defaults are exercised.
class _MinimalStateStrategy extends SaveStrategy with StateSyncCapable {
  @override
  String get strategyId => 'minimal';
  @override
  Future<String?> getSaveDir(Game game, String romPath) async => null;
  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
          {DateTime? sessionStart, String syncMode = 'both'}) async => [];
  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async => false;
  @override
  Future<String> stateDirectory(Game game, String romPath) async => '';
  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async => null;
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('state_defaults'));
  tearDown(() => tmp.delete(recursive: true));

  test('slotOf defaults to an unknown slot named after the file', () {
    expect(_MinimalStateStrategy().slotOf('a.sav'), const UnknownStateSlot('a.sav'));
  });

  test('describeState defaults to the modified time and no version', () async {
    final file = File(p.join(tmp.path, 'a.sav'))..writeAsBytesSync([1, 2, 3]);
    final when = DateTime(2026, 3, 4, 5, 6, 7);
    file.setLastModifiedSync(when);
    final info = await _MinimalStateStrategy().describeState(file);
    expect(info.savedAt, when);
    expect(info.emulatorVersion, isNull);
    expect(info.formatId, isNull);
  });

  test('describeState never throws for a missing file', () async {
    final info = await _MinimalStateStrategy().describeState(File(p.join(tmp.path, 'gone.sav')));
    expect(info.emulatorVersion, isNull);
  });

  test('stateScreenshot defaults to null', () async {
    final file = File(p.join(tmp.path, 'a.sav'))..writeAsBytesSync([1]);
    expect(await _MinimalStateStrategy().stateScreenshot(file), isNull);
  });

  test('emulators report no installed version by default', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final registry = StrategyRegistry(DirectoryService(prefs), prefs);
    expect(await registry.getStrategyById('duckstation')!.installedVersion(), isNull);
    expect(await registry.getStrategyById('retroarch')!.installedVersion(), isNull);
  });
}
