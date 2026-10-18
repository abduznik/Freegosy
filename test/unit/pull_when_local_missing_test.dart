import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'save_sync_service_test.mocks.dart';

/// RomM 4.9+ remembers which save version each device last synced. "Current on this device" must not stop a
/// pull when the local save is gone, or a deleted folder / reinstalled game never gets its save back.
void main() {
  late Directory tmp;
  late MockRommService romm;
  late MockDirectoryService dirs;
  late SaveSyncService service;
  final game = Game(id: '7', name: 'Monkey Island', platformSlug: 'scummvm', fileSize: 0);

  Uint8List zipOf(String name, String text) {
    final archive = Archive()..addFile(ArchiveFile(name, text.length, text.codeUnits));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pull_missing');
    SharedPreferences.setMockInitialValues({'romm_device_id': 'dev1'});
    romm = MockRommService();
    dirs = MockDirectoryService();
    when(dirs.getEmulatorAppSupportDirectory(any, platformSlug: anyNamed('platformSlug'))).thenAnswer((_) async => tmp.path);
    when(dirs.getEmulatorDirectory('temp')).thenAnswer((_) async => Directory.systemTemp.path);
    when(dirs.linuxSyncPreset).thenReturn('default');
    when(romm.fetchCapabilities()).thenAnswer((_) async => RommCapabilities(version: '5.0.0'));
    when(romm.getLatestSave('7', deviceId: 'dev1')).thenAnswer((_) async => {
          'file_name': 'save.zip',
          'download_path': 'http://fake/save.zip',
          'updated_at': DateTime.now().toIso8601String(),
          'device_syncs': <dynamic>[
            {'device_id': 'dev1', 'is_current': true},
          ],
        });
    when(romm.downloadSave(any, prefs: anyNamed('prefs'), deviceId: anyNamed('deviceId'))).thenAnswer((_) async => zipOf('monkey.s01', 'cloud save'));
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    service = SaveSyncService(romm, dirs, MockStrategyRegistry(), prefs);
  });
  tearDown(() => tmp.delete(recursive: true));

  final saveFolder = () => p.join(tmp.path, 'freegosy_saves', '7');

  test('a save that is current on this device and still on disk is left alone', () async {
    Directory(saveFolder()).createSync(recursive: true);
    File(p.join(saveFolder(), 'monkey.s01')).writeAsStringSync('local save');
    expect(await service.pullSave(game, '/roms/monkey', emulatorId: 'scummvm'), isFalse);
    verifyNever(romm.downloadSave(any, prefs: anyNamed('prefs'), deviceId: anyNamed('deviceId')));
    expect(File(p.join(saveFolder(), 'monkey.s01')).readAsStringSync(), 'local save');
  });

  test('the same save is restored when the local copy is gone', () async {
    expect(await service.pullSave(game, '/roms/monkey', emulatorId: 'scummvm'), isTrue);
    verify(romm.downloadSave(any, prefs: anyNamed('prefs'), deviceId: anyNamed('deviceId'))).called(1);
    expect(File(p.join(saveFolder(), 'monkey.s01')).readAsStringSync(), 'cloud save');
  });
}
