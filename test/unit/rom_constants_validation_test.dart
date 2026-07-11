import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/rom_constants.dart';

void main() {
  group('RomConstants validation', () {
    test('all platform slugs have non-empty extension lists', () {
      for (final entry in RomConstants.platformExtensions.entries) {
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

    test('windows platform includes .exe extension', () {
      expect(RomConstants.platformExtensions['windows'], contains('.exe'));
      expect(RomConstants.platformExtensions['pc'], contains('.exe'));
      expect(RomConstants.platformExtensions['win'], contains('.exe'));
    });

    test('windows platform includes .bat and .cmd extensions', () {
      expect(RomConstants.platformExtensions['win'], contains('.bat'));
      expect(RomConstants.platformExtensions['win'], contains('.cmd'));
    });
  });
}
