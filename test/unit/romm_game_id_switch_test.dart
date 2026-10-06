import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/save_strategy.dart';
import 'package:freegosy/core/save/strategies/eden_save_strategy.dart';
import 'package:freegosy/core/save/strategies/ryujinx_save_strategy.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_id_test_env.dart';

void main() {
  const platform = PlatformInfo('windows', environment: {'APPDATA': ''});
  Game game({String? titleId}) => Game(id: 's', name: 'Some Game', platformSlug: 'switch', fileSize: 0, titleId: titleId);

  late Directory tmp;
  late String romPath; // an empty .nsp: no title id in its header or its name
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('romm_switch');
    romPath = p.join(tmp.path, 'Some Game.nsp');
    File(romPath).writeAsBytesSync(const []);
  });
  tearDown(() => tmp.delete(recursive: true));

  for (final (name, make) in <(String, Future<dynamic> Function())>[
    ('Eden', () async => EdenSaveStrategy(await StubDirectoryService.create(), platform: platform)),
    ('Ryujinx', () async => RyujinxSaveStrategy(platform: platform)),
  ]) {
    group(name, () {
      test('RomM\'s title id, upper case, before the ROM and any cached mapping', () async {
        final strategy = await make();
        strategy.setManualMapping('0100000000000000');
        expect(await strategy.resolveTitleId(r'C:\nope\Some Game.nsp', game(titleId: '0100abcd12345000')),
            '0100ABCD12345000');
      });

      test('without it: the cached mapping, as before', () async {
        final strategy = await make();
        strategy.setManualMapping('0100000000000000');
        expect(await strategy.resolveTitleId(romPath, game()), '0100000000000000');
      });

      test('without either: asks for the folder, as before', () async {
        final strategy = await make();
        expect(() => strategy.resolveTitleId(romPath, game()), throwsA(isA<SaveMappingRequiredException>()));
      });
    });
  }

  group('RomM Switch ids that need care', () {
    test('an update\'s id becomes the base game\'s, where the saves are', () async {
      final strategy = EdenSaveStrategy(await StubDirectoryService.create(), platform: platform);
      expect(await strategy.resolveTitleId(romPath, game(titleId: '0100ABCD12345800')), '0100ABCD12345000');
    });

    test('a RomM value that isn\'t a title id is ignored', () async {
      final strategy = RyujinxSaveStrategy(platform: platform);
      strategy.setManualMapping('0100000000000000');
      expect(await strategy.resolveTitleId(romPath, game(titleId: '../../x')), '0100000000000000');
    });

    test('Eden restore puts the save in RomM\'s title folder', () async {
      final exe = p.join(tmp.path, 'eden', 'eden.exe');
      File(exe).createSync(recursive: true);
      final profile = p.join(tmp.path, 'eden', 'user', 'nand', 'user', 'save', '0000000000000000', 'a' * 32);
      Directory(p.join(profile, '0100000000010000')).createSync(recursive: true);
      File(p.join(profile, '0100000000010000', 'data.bin')).writeAsBytesSync([1]);
      final eden = EdenSaveStrategy(await StubDirectoryService.create(exePath: exe), platform: platform);

      final ok = await eden.restoreSave(
          game(titleId: '0100ABCD12345000'), r'C:\nope\Some Game.nsp', Uint8List.fromList([7, 7, 7]), 'save.dat');

      expect(ok, isTrue);
      expect(File(p.join(profile, '0100ABCD12345000', 'save.dat')).readAsBytesSync(), [7, 7, 7]);
    });
  });
}
