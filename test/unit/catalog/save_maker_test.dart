import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/catalog/save_maker.dart';

void main() {
  const ids = {'retroarch', 'ares', 'duckstation', 'mgba', 'pcsx2'};

  test('a RetroArch core name is RetroArch with that core', () {
    expect(resolveSaveMaker('mupen64plus_next', emulatorIds: ids), const SaveMaker('retroarch', coreId: 'mupen64plus_next'));
    expect(resolveSaveMaker('pcsx_rearmed_libretro', emulatorIds: ids), const SaveMaker('retroarch', coreId: 'pcsx_rearmed'));
  });

  test('a standalone emulator id is that emulator', () {
    expect(resolveSaveMaker('ares', emulatorIds: ids), const SaveMaker('ares'));
    expect(resolveSaveMaker('DuckStation', emulatorIds: ids), const SaveMaker('duckstation'));
  });

  test('a name that is both a standalone emulator and a core is the standalone emulator', () {
    // Freegosy uploads standalone mGBA saves tagged `mgba`.
    expect(resolveSaveMaker('mgba', emulatorIds: ids), const SaveMaker('mgba'));
  });

  test('freegosy, empty, null and unknown tags are an unknown maker', () {
    for (final tag in ['freegosy', '', '  ', null, 'some_new_emulator', 'retroarch']) {
      expect(resolveSaveMaker(tag, emulatorIds: ids), isNull, reason: '$tag');
    }
  });

  test('the tag is the core for RetroArch and the id otherwise', () {
    expect(const SaveMaker('retroarch', coreId: 'mupen64plus_next').tag, 'mupen64plus_next');
    expect(const SaveMaker('ares').tag, 'ares');
  });

  test('kKnownEmulatorIds holds the emulator definitions', () {
    expect(kKnownEmulatorIds, containsAll(['retroarch', 'ares', 'duckstation', 'pcsx2']));
  });
}
