import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/rom_lookup_service.dart';

/// #194: the largest file of a DOS game folder is often a resource, not the program.
void main() {
  late Directory root;
  final game = Game(id: '1', name: '(한)다크사이드 스토리', platformSlug: 'dos', fileSize: 1);

  File put(String path, int size) {
    final f = File('${root.path}/$path')..createSync(recursive: true);
    f.writeAsBytesSync(List.filled(size, 1));
    return f;
  }

  setUp(() async => root = await Directory.systemTemp.createTemp('dos'));
  tearDown(() => root.delete(recursive: true));

  test('prefers the launcher script at the top of the folder', () async {
    put('PLAY.BAT', 20);
    put('Darkside/DARKSIDE.EXE', 1000);
    put('Darkside/SETUP.EXE', 500);
    put('Darkside/ANIMATE.SON', 90000);
    expect(await RomLookupService.findMainRomInFolder(game, root.path), '${root.path}/PLAY.BAT');
  });

  test('without a script it picks the game program, not the data file or setup', () async {
    put('Darkside/DARKSIDE.EXE', 1000);
    put('Darkside/SETUP.EXE', 5000);
    put('Darkside/ANIMATE.SON', 90000);
    expect(await RomLookupService.findMainRomInFolder(game, root.path), '${root.path}/Darkside/DARKSIDE.EXE');
  });

  test('a folder with only data files has no entry point', () async {
    put('Darkside/ANIMATE.SON', 90000);
    expect(await RomLookupService.pickDosEntryPoint(root.path), isNull);
  });

  test('a disc image still falls back to the platform extensions', () async {
    put('game.iso', 5000);
    put('readme.txt', 90000);
    expect(await RomLookupService.findMainRomInFolder(game, root.path), '${root.path}/game.iso');
  });
}
