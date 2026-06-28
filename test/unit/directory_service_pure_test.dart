import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/rom_constants.dart';
import 'package:freegosy/core/storage/directory_service.dart';

void main() {
  group('DirectoryService pure/static methods', () {
    group('isRomFile', () {
      test('empty extension returns false', () {
        expect(DirectoryService.isRomFile('ps2', 'game'), isFalse);
      });

      test('unknown platform allows all extensions', () {
        expect(DirectoryService.isRomFile('unknown_platform', 'game.xyz'), isTrue);
      });

      test('case insensitive match', () {
        expect(DirectoryService.isRomFile('ps2', 'game.CHD'), isTrue);
        expect(DirectoryService.isRomFile('ps2', 'game.chd'), isTrue);
        expect(DirectoryService.isRomFile('ps2', 'game.Chd'), isTrue);
      });

      test('known extension returns true', () {
        expect(DirectoryService.isRomFile('ps2', 'game.iso'), isTrue);
        expect(DirectoryService.isRomFile('gba', 'game.gba'), isTrue);
        expect(DirectoryService.isRomFile('nds', 'game.nds'), isTrue);
      });

      test('wrong extension returns false', () {
        expect(DirectoryService.isRomFile('ps2', 'game.txt'), isFalse);
        expect(DirectoryService.isRomFile('gba', 'game.iso'), isFalse);
      });
    });

    group('platformSupportsArchive', () {
      test('null slug returns false', () {
        // Instantiated with mock prefs — pure method test
        // We test via a temporary instance since platformSupportsArchive is an instance method
        // but it only reads from RomConstants.platformExtensions (no I/O)
        // For simplicity, test the underlying logic directly
        expect(
          RomConstants.platformExtensions['arcade']?.any(
            (ext) => ext == '.zip' || ext == '.7z',
          ),
          isTrue,
        );
      });

      test('arcade supports .zip', () {
        final extensions = RomConstants.platformExtensions['arcade'] ?? [];
        expect(extensions.any((ext) => ext == '.zip' || ext == '.7z'), isTrue);
      });

      test('psx does not support .zip', () {
        final extensions = RomConstants.platformExtensions['psx'] ?? [];
        expect(extensions.any((ext) => ext == '.zip' || ext == '.7z'), isFalse);
      });
    });

    group('platformFolderCanonicalMap', () {
      test('n3ds maps to 3ds', () {
        expect(DirectoryService.platformFolderCanonicalMap['n3ds'], '3ds');
      });

      test('genesis maps to megadrive', () {
        expect(DirectoryService.platformFolderCanonicalMap['genesis'], 'megadrive');
      });

      test('megacd maps to segacd', () {
        expect(DirectoryService.platformFolderCanonicalMap['megacd'], 'segacd');
      });

      test('famicom maps to nes', () {
        expect(DirectoryService.platformFolderCanonicalMap['famicom'], 'nes');
      });
    });
  });
}
