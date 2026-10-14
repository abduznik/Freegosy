import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/disc/multi_disc_resolver.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/rom_lookup_service.dart';
import 'package:path/path.dart' as p;

/// #54: Tales of Symphonia as downloaded from RomM.
void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('multidisc_'));
  tearDown(() async => dir.delete(recursive: true));

  Future<void> put(String name, {int size = 10, String? text}) async {
    final f = File(p.join(dir.path, name));
    text != null ? await f.writeAsString(text) : await f.writeAsBytes(List.filled(size, 0));
  }

  Game gc() => Game(
        id: '1', name: 'Tales of Symphonia', platformSlug: 'ngc',
        fsName: 'Tales of Symphonia', fileName: 'Tales of Symphonia', fileSize: 1000,
        hasMultipleFiles: true,
      );

  test('discNumber reads the common spellings', () {
    expect(MultiDiscResolver.discNumber('Tales of Symphonia (USA) (Disc 2).rvz'), 2);
    expect(MultiDiscResolver.discNumber('Game (Disk 3).chd'), 3);
    expect(MultiDiscResolver.discNumber('Game CD1.bin'), 1);
    expect(MultiDiscResolver.discNumber('Game (USA).iso'), isNull);
  });

  test('no .m3u: boots disc 1 even though disc 2 is the larger file', () async {
    await put('Tales of Symphonia (USA) (Disc 1).rvz', size: 100);
    await put('Tales of Symphonia (USA) (Disc 2).rvz', size: 900);
    final path = await RomLookupService.findMainRomInFolder(gc(), dir.path);
    // ignore: avoid_print
    print('no m3u -> ${p.basename(path!)}');
    expect(p.basename(path), 'Tales of Symphonia (USA) (Disc 1).rvz');
  });

  test('a single-disc folder still picks the largest file', () async {
    await put('Game (USA).rvz', size: 100);
    await put('Game (USA) (Bonus).rvz', size: 900);
    final path = await RomLookupService.findMainRomInFolder(gc(), dir.path);
    expect(p.basename(path!), 'Game (USA) (Bonus).rvz');
  });

  test('.m3u: lists the playlist first, then the discs it names', () async {
    await put('Tales of Symphonia (USA) (Disc 1).rvz');
    await put('Tales of Symphonia (USA) (Disc 2).rvz');
    await put('Tales of Symphonia (USA).m3u',
        text: '#EXTM3U\nTales of Symphonia (USA) (Disc 1).rvz\nTales of Symphonia (USA) (Disc 2).rvz\nmissing.rvz\n');
    final main = await RomLookupService.findMainRomInFolder(gc(), dir.path);
    final discs = await MultiDiscResolver.discsFor(main!);
    // ignore: avoid_print
    print('picker entries: ${discs.map((d) => d['file_name']).toList()}');
    expect(discs.map((d) => d['file_name']), [
      'Tales of Symphonia (USA).m3u',
      'Tales of Symphonia (USA) (Disc 1).rvz',
      'Tales of Symphonia (USA) (Disc 2).rvz',
    ]);
  });

  test('no .m3u: siblings of the chosen disc form the picker list', () async {
    await put('Baten Kaitos (Disc 1).rvz');
    await put('Baten Kaitos (Disc 2).rvz');
    await put('Baten Kaitos Origins (Disc 1).rvz');
    final discs = await MultiDiscResolver.discsFor(p.join(dir.path, 'Baten Kaitos (Disc 1).rvz'));
    expect(discs.map((d) => d['file_name']), ['Baten Kaitos (Disc 1).rvz', 'Baten Kaitos (Disc 2).rvz']);
  });

  test('single-disc game and a one-disc playlist give no picker', () async {
    await put('Solo (USA).rvz');
    expect(await MultiDiscResolver.discsFor(p.join(dir.path, 'Solo (USA).rvz')), isEmpty);
    await put('Solo.m3u', text: 'Solo (USA).rvz\n');
    expect(await MultiDiscResolver.discsFor(p.join(dir.path, 'Solo.m3u')), isEmpty);
  });
}
