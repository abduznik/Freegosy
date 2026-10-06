import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/ppsspp_save_strategy.dart';
import 'package:freegosy/core/save/strategies/rpcs3_save_strategy.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_id_test_env.dart';

void main() {
  late Directory base;
  setUp(() async => base = await Directory.systemTemp.createTemp('romm_folders'));
  tearDown(() => base.delete(recursive: true));

  void folder(String path) {
    Directory(path).createSync(recursive: true);
    File(p.join(path, 'DATA.BIN')).writeAsBytesSync(List.filled(64, 1));
  }

  /// A PARAM.SFO holding only TITLE = [title], so the old title guess would
  /// pick this folder for a game named [title].
  void paramSfo(String folderPath, String title, {List<String> keys = const []}) {
    // Extra keys are only listed in the key table (no entries): enough for a
    // check that looks for their names in the file.
    final key = [...utf8.encode('TITLE'), 0, for (final k in keys) ...[...utf8.encode(k), 0], 0, 0];
    final value = [...utf8.encode(title), 0];
    const keyTable = 20 + 16;
    final dataTable = keyTable + key.length;
    final b = ByteData(dataTable + value.length);
    for (final (i, c) in [0, 0x50, 0x53, 0x46].indexed) {
      b.setUint8(i, c);
    }
    b.setUint32(4, 0x101, Endian.little);
    b.setUint32(8, keyTable, Endian.little);
    b.setUint32(12, dataTable, Endian.little);
    b.setUint32(16, 1, Endian.little);
    b.setUint16(20, 0, Endian.little); // key offset
    b.setUint16(22, 0x0204, Endian.little); // utf8
    b.setUint32(24, value.length, Endian.little);
    b.setUint32(28, value.length, Endian.little);
    b.setUint32(32, 0, Endian.little); // data offset
    final bytes = b.buffer.asUint8List()
      ..setAll(keyTable, key)
      ..setAll(dataTable, value);
    File(p.join(folderPath, 'PARAM.SFO')).writeAsBytesSync(bytes);
  }

  group('RPCS3', () {
    String savedata() => p.join(base.path, 'rpcs3', 'dev_hdd0', 'home', '00000001', 'savedata');

    Future<Rpcs3SaveStrategy> rpcs3() async {
      final exe = p.join(base.path, 'rpcs3', 'rpcs3.exe');
      File(exe).createSync(recursive: true);
      Directory(savedata()).createSync(recursive: true);
      return Rpcs3SaveStrategy(await StubDirectoryService.create(exePath: exe),
          platform: const PlatformInfo('windows', environment: {}));
    }

    test('every folder starting with RomM\'s title id, and no other game\'s', () async {
      final strategy = await rpcs3();
      folder(p.join(savedata(), 'BLUS31426'));
      folder(p.join(savedata(), 'BLUS31426-AUTOSAVE'));
      folder(p.join(savedata(), 'BLES00001'));

      final files = await strategy.getSaveFiles(
          Game(id: 'r', name: 'Some Game', platformSlug: 'ps3', fileSize: 0, titleId: 'blus31426'), r'C:\nope\game');

      expect(files.map((f) => p.basename(f.path)).toSet(), {'BLUS31426', 'BLUS31426-AUTOSAVE'});
    });

    test('a game RomM identified with no folder yet has no saves (no guessing)', () async {
      final strategy = await rpcs3();
      folder(p.join(savedata(), 'BLES00001'));
      paramSfo(p.join(savedata(), 'BLES00001'), 'Some Game');
      final files = await strategy.getSaveFiles(
          Game(id: 'r', name: 'Some Game', platformSlug: 'ps3', fileSize: 0, titleId: 'BLUS31426'), r'C:\nope\game');
      expect(files, isEmpty);
    });
  });

  group('PPSSPP', () {
    Future<PpssppSaveStrategy> ppsspp() async => PpssppSaveStrategy(await StubDirectoryService.create(),
        platform: PlatformInfo('windows', environment: {'USERPROFILE': base.path}));

    String savedata() => p.join(base.path, 'Documents', 'PPSSPP', 'PSP', 'SAVEDATA');

    test('every folder starting with RomM\'s save_target, and no other game\'s', () async {
      folder(p.join(savedata(), 'ULUS10064DATA00'));
      folder(p.join(savedata(), 'ULUS10064SETTINGS'));
      folder(p.join(savedata(), 'NPUH10000X'));

      final files = await (await ppsspp()).getSaveFiles(
          Game(id: 'p', name: 'Some Game', platformSlug: 'psp', fileSize: 0, saveTarget: 'ULUS10064'), r'C:\nope\g.iso');

      expect(files.map((f) => p.basename(f.path)).toSet(), {'ULUS10064DATA00', 'ULUS10064SETTINGS'});
    });

    test('a game RomM identified with no folder yet has no saves (not the newest folder)', () async {
      folder(p.join(savedata(), 'NPUH10000X'));
      paramSfo(p.join(savedata(), 'NPUH10000X'), 'Some Game');
      final files = await (await ppsspp()).getSaveFiles(
          Game(id: 'p', name: 'Some Game', platformSlug: 'psp', fileSize: 0, saveTarget: 'ULUS10064'), r'C:\nope\g.iso');
      expect(files.where((f) => p.isWithin(savedata(), f.path)), isEmpty);
    });
  });

  group('RomM PS3/PSP ids that need care', () {
    String rpcs3Savedata() => p.join(base.path, 'rpcs3', 'dev_hdd0', 'home', '00000001', 'savedata');
    String pspSavedata() => p.join(base.path, 'Documents', 'PPSSPP', 'PSP', 'SAVEDATA');

    Future<Rpcs3SaveStrategy> rpcs3() async {
      final exe = p.join(base.path, 'rpcs3', 'rpcs3.exe');
      File(exe).createSync(recursive: true);
      Directory(rpcs3Savedata()).createSync(recursive: true);
      return Rpcs3SaveStrategy(await StubDirectoryService.create(exePath: exe),
          platform: const PlatformInfo('windows', environment: {}));
    }

    test('RPCS3: a hyphenated title id still finds the folders; save_target is used first', () async {
      final strategy = await rpcs3();
      folder(p.join(rpcs3Savedata(), 'BLUS31426'));
      folder(p.join(rpcs3Savedata(), 'BLUS31426-AUTOSAVE'));
      for (final g in [
        Game(id: 'r', name: 'Some Game', platformSlug: 'ps3', fileSize: 0, titleId: 'BLUS-31426'),
        Game(id: 'r', name: 'Some Game', platformSlug: 'ps3', fileSize: 0, titleId: 'NOPE', saveTarget: 'BLUS31426'),
      ]) {
        final files = await strategy.getSaveFiles(g, r'C:\nope\game');
        expect(files.map((f) => p.basename(f.path)).toSet(), {'BLUS31426', 'BLUS31426-AUTOSAVE'}, reason: g.titleId);
      }
    });

    test('PPSSPP: installed game data under the same id stays out; saves (and folders without PARAM.SFO) go', () async {
      folder(p.join(pspSavedata(), 'ULUS10064DATA00'));
      paramSfo(p.join(pspSavedata(), 'ULUS10064DATA00'), 'Save', keys: const ['SAVEDATA_FILE_LIST', 'SAVEDATA_PARAMS']);
      folder(p.join(pspSavedata(), 'ULUS10064SETTINGS'));
      folder(p.join(pspSavedata(), 'ULUS10064INSTALL'));
      paramSfo(p.join(pspSavedata(), 'ULUS10064INSTALL'), 'Install');

      final files = await PpssppSaveStrategy(await StubDirectoryService.create(),
              platform: PlatformInfo('windows', environment: {'USERPROFILE': base.path}))
          .getSaveFiles(Game(id: 'p', name: 'Some Game', platformSlug: 'psp', fileSize: 0, saveTarget: 'ULUS-10064'),
              r'C:\nope\g.iso');

      expect(files.map((f) => p.basename(f.path)).toSet(), {'ULUS10064DATA00', 'ULUS10064SETTINGS'});
    });
  });
}
