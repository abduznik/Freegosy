import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/save/strategies/ares_save_strategy.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// What RomM keeps for a save: the uploaded filename and its bytes.
class _RommStore {
  String? fileName;
  Uint8List? bytes;
}

/// Push → RomM → wipe the machine → pull, as a second device would, with the
/// real Ares strategy on Linux (case-sensitive) under a temp HOME. Ares names
/// its save after the game file with the case kept (`Location::prefix`).
void main() {
  late Directory tmp;
  late Directory savesDir;
  late AresSaveStrategy strategy;
  final store = _RommStore();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ares_roundtrip_');
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    strategy = AresSaveStrategy(
      DirectoryService(prefs),
      platform: PlatformInfo('linux', environment: {'HOME': tmp.path}),
    );
    savesDir = Directory(p.join(tmp.path, '.local', 'share', 'ares', 'Saves', 'Game Boy Advance'));
    await savesDir.create(recursive: true);
    store..fileName = null..bytes = null;
  });

  tearDown(() => tmp.delete(recursive: true));

  final game = Game(id: '7', name: 'Pokemon Emerald (USA)', platformSlug: 'gba', fileSize: 0);
  String rom() => p.join(tmp.path, 'roms', 'Pokemon Emerald (USA).gba');

  Future<void> push() async {
    final files = await strategy.getSaveFiles(game, rom());
    expect(files, hasLength(1), reason: 'the save ares wrote must be found');
    store
      ..fileName = SaveSyncService.normalizeSaveFilename(p.basename(files.single.path))
      ..bytes = await files.single.readAsBytes();
  }

  Future<bool> pull() => strategy.restoreSave(game, rom(), store.bytes!, store.fileName!);

  test('a save pulled on a fresh machine lands where ares reads it', () async {
    final save = File(p.join(savesDir.path, 'Pokemon Emerald (USA).ram'));
    await save.writeAsBytes(List.generate(256, (i) => i));
    await push();
    await save.delete();

    expect(await pull(), isTrue);

    final names = savesDir.listSync().map((e) => p.basename(e.path)).toList();
    // ignore: avoid_print
    print('files in ares Saves/ after pull: $names');
    final restored = File(p.join(savesDir.path, 'Pokemon Emerald (USA).ram'));
    expect(await restored.exists(), isTrue, reason: 'ares opens Saves/<System>/<game file name>.ram, same case');
    expect(await restored.readAsBytes(), List.generate(256, (i) => i));
  });

  test('a pull overwrites the existing save instead of adding a second file', () async {
    final save = File(p.join(savesDir.path, 'Pokemon Emerald (USA).ram'));
    await save.writeAsBytes(List.filled(200, 1));
    await push();
    await save.writeAsBytes(List.filled(200, 2)); // older progress on this machine

    expect(await pull(), isTrue);

    expect(savesDir.listSync().whereType<File>().where((f) => f.path.endsWith('.ram')), hasLength(1));
    expect(await save.readAsBytes(), List.filled(200, 1));
  });
}
