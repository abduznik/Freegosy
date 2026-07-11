import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/rom_constants.dart';

void main() {
  group('RomConstants validation', () {
    test('all platform slugs have non-empty extension lists', () {
      // Folder-based platforms (windows, pc, win) have empty lists by design —
      // they return the game folder path, and the emulator strategy finds the exe.
      const folderBasedPlatforms = {'windows', 'pc', 'win'};
      for (final entry in RomConstants.platformExtensions.entries) {
        if (folderBasedPlatforms.contains(entry.key)) continue;
        expect(
          entry.value,
          isNotEmpty,
          reason: 'Platform "${entry.key}" has empty extension list',
        );
      }
    });

    test('psx includes .chd extension', () {
      expect(RomConstants.platformExtensions['psx'], contains('.chd'));
    });

    test('ps2 includes .chd extension', () {
      expect(RomConstants.platformExtensions['ps2'], contains('.chd'));
    });

    test('windows platform has empty extension list (folder-based)', () {
      expect(RomConstants.platformExtensions['windows'], isEmpty);
      expect(RomConstants.platformExtensions['pc'], isEmpty);
      expect(RomConstants.platformExtensions['win'], isEmpty);
    });
  });
}
