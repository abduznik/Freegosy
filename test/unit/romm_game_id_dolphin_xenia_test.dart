import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/dolphin_save_strategy.dart';
import 'package:freegosy/core/save/strategies/xenia_save_strategy.dart';

import '../helpers/game_id_test_env.dart';

void main() {
  group('Dolphin game id', () {
    Future<DolphinSaveStrategy> dolphin() async =>
        DolphinSaveStrategy(await StubDirectoryService.create(), platform: const PlatformInfo('windows', environment: {}));

    test('GameCube: RomM\'s save_target, for any file type', () async {
      final id = await (await dolphin()).gameIdFor(
          Game(id: 'g', name: 'Zelda', platformSlug: 'ngc', fileSize: 0, saveTarget: 'gzle'), r'C:\nope\Zelda.wbfs');
      expect(id, 'GZLE');
    });

    test('Wii: RomM\'s hex save_target becomes the ASCII game id', () async {
      final id = await (await dolphin()).gameIdFor(
          Game(id: 'w', name: 'Zelda', platformSlug: 'wii', fileSize: 0, saveTarget: '525a5445'), r'C:\nope\Zelda.rvz');
      expect(id, 'RZTE');
    });

    test('Wii WAD (a path, not a disc id) and no RomM value: the file is read as before', () async {
      final d = await dolphin();
      expect(
          await d.gameIdFor(
              Game(id: 'w', name: 'Wad', platformSlug: 'wii', fileSize: 0, saveTarget: '00010001/574b5445'), r'C:\nope\x.wad'),
          isNull);
      expect(await d.gameIdFor(Game(id: 'g', name: 'Zelda', platformSlug: 'ngc', fileSize: 0), r'C:\nope\x.wbfs'), isNull);
    });
  });

  group('Xenia title id', () {
    test('RomM\'s title_id, upper case', () {
      expect(
          XeniaSaveStrategy.titleIdFor(
              Game(id: 'x', name: 'Halo 3', platformSlug: 'xbox360', fileSize: 0, titleId: '4d5307e6')),
          '4D5307E6');
    });

    test('without it, the file name as before', () {
      expect(XeniaSaveStrategy.titleIdFor(Game(id: 'x', name: 'Halo 3 [4D5307E6]', platformSlug: 'xbox360', fileSize: 0)),
          '4D5307E6');
    });
  });

  group('RomM ids that need care', () {
    test('Dolphin: a 6-character GameCube id is cut to the 4 GCI names use', () async {
      final d = DolphinSaveStrategy(await StubDirectoryService.create(), platform: const PlatformInfo('windows', environment: {}));
      expect(
          await d.gameIdFor(Game(id: 'g', name: 'Zelda', platformSlug: 'ngc', fileSize: 0, saveTarget: 'GZLE01'), r'C:\nope\z.iso'),
          'GZLE');
    });

    test('Xenia: a RomM value that isn\'t 8 hex digits falls back to the file name', () {
      expect(
          XeniaSaveStrategy.titleIdFor(
              Game(id: 'x', name: 'Halo 3 [4D5307E6]', platformSlug: 'xbox360', fileSize: 0, titleId: '../../x')),
          '4D5307E6');
    });
  });
}
