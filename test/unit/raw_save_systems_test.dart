import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/catalog/save_entry.dart';
import 'package:freegosy/core/save/catalog/save_fit.dart';
import 'package:freegosy/core/save/catalog/save_maker.dart';
import 'package:freegosy/core/save/formats/save_format_registry.dart';

void main() {
  SaveEntry romm(SaveMaker m) => SaveEntry(source: SaveSource.romm, fileName: 'x', savedAt: DateTime(2026), maker: m, tag: m.tag);

  test('NDS: melonDS and both RetroArch melonDS cores share one save', () {
    const ds = SaveMaker('retroarch', coreId: 'melondsds');
    const melon = SaveMaker('melonds');
    expect(fitFor(romm(ds), platformSlug: 'nds', picked: melon, platformDefault: melon, installed: const {'melonds', 'retroarch'}).kind,
        SaveFitKind.native);
    expect(fitFor(romm(melon), platformSlug: 'nds', picked: ds, platformDefault: melon, installed: const {'melonds', 'retroarch'}).kind,
        SaveFitKind.native);
  });

  test('NDS saves are found under RomM\'s other slugs for the DS', () {
    for (final slug in ['nds', 'nintendo-ds']) {
      expect(saveSystemFor(slug)?.name, 'NDS', reason: slug);
    }
  });

  test('a raw save is used as it is', () {
    final files = [SaveBlob('Game.srm', Uint8List.fromList([1, 2, 3]))];
    expect(convertSave(platformSlug: 'nds', files: files, sourceTag: 'melondsds', targetTag: 'melonds', stem: 'Game'),
        isA<SaveAsIs>());
  });

  test('a save from an emulator not on the raw line does not fit it (DeSmuME into melonDS)', () {
    const desmume = SaveMaker('retroarch', coreId: 'desmume2015');
    for (final picked in const [SaveMaker('melonds'), SaveMaker('retroarch', coreId: 'melonds')]) {
      expect(fitFor(romm(desmume), platformSlug: 'nds', picked: picked, platformDefault: picked, installed: const {'melonds', 'retroarch'}).kind,
          SaveFitKind.unusable, reason: '$picked');
    }
  });

  test('a raw format is chosen by tag only, never by the file alone', () {
    final files = [SaveBlob('Game.dsv', Uint8List.fromList([1, 2, 3]))];
    expect(convertSave(platformSlug: 'nds', files: files, sourceTag: 'desmume2015', targetTag: 'melonds', stem: 'Game'),
        isA<SaveNotConvertible>());
    expect(convertSave(platformSlug: 'nds', files: files, targetTag: 'melonds', stem: 'Game'), isA<SaveNotConvertible>());
  });
}
