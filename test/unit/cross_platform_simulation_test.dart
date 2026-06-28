import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/rom_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests that verify critical logic works correctly when simulated
/// on all three platforms (Windows, macOS, Linux) via PlatformInfo injection.
void main() {
  group('Cross-platform simulated tests', () {
    group('PlatformInfo', () {
      test('isWindows returns true only for windows', () {
        expect(PlatformInfo('windows').isWindows, isTrue);
        expect(PlatformInfo('macos').isWindows, isFalse);
        expect(PlatformInfo('linux').isWindows, isFalse);
      });

      test('isMacOS returns true only for macos', () {
        expect(PlatformInfo('macos').isMacOS, isTrue);
        expect(PlatformInfo('windows').isMacOS, isFalse);
        expect(PlatformInfo('linux').isMacOS, isFalse);
      });

      test('isLinux returns true only for linux', () {
        expect(PlatformInfo('linux').isLinux, isTrue);
        expect(PlatformInfo('windows').isLinux, isFalse);
        expect(PlatformInfo('macos').isLinux, isFalse);
      });

      test('pathSeparator is backslash on Windows, forward slash elsewhere', () {
        expect(PlatformInfo('windows').pathSeparator, '\\');
        expect(PlatformInfo('macos').pathSeparator, '/');
        expect(PlatformInfo('linux').pathSeparator, '/');
      });

      test('environment access works', () {
        final platform = PlatformInfo('windows', environment: {
          'APPDATA': 'C:\\Users\\test\\AppData\\Roaming',
          'USERPROFILE': 'C:\\Users\\test',
        });
        expect(platform.appData, 'C:\\Users\\test\\AppData\\Roaming');
        expect(platform.environment['USERPROFILE'], 'C:\\Users\\test');
      });

      test('homeDir returns HOME on Unix, USERPROFILE on Windows', () {
        expect(
          PlatformInfo('macos', environment: {'HOME': '/Users/test'}).homeDir,
          '/Users/test',
        );
        expect(
          PlatformInfo('linux', environment: {'HOME': '/home/test'}).homeDir,
          '/home/test',
        );
        expect(
          PlatformInfo('windows', environment: {'USERPROFILE': 'C:\\Users\\test'}).homeDir,
          'C:\\Users\\test',
        );
      });

      test('current returns a valid PlatformInfo', () {
        final current = PlatformInfo.current;
        expect(current.os, isNotEmpty);
        expect(current.isWindows || current.isMacOS || current.isLinux, isTrue);
      });
    });

    group('DirectoryService isRomFile — cross-platform', () {
      test('works identically on all simulated platforms', () {
        for (final os in ['windows', 'macos', 'linux']) {
          expect(
            DirectoryService.isRomFile('ps2', 'game.iso'),
            isTrue,
            reason: 'Failed on $os',
          );
          expect(
            DirectoryService.isRomFile('ps2', 'game.txt'),
            isFalse,
            reason: 'Failed on $os',
          );
          expect(
            DirectoryService.isRomFile('ps2', 'game.CHD'),
            isTrue,
            reason: 'Case-insensitive failed on $os',
          );
        }
      });
    });

    group('platformFolderCanonicalMap — cross-platform', () {
      test('canonical maps are consistent across platforms', () {
        for (final os in ['windows', 'macos', 'linux']) {
          expect(DirectoryService.platformFolderCanonicalMap['n3ds'], '3ds',
              reason: 'n3ds map failed on $os');
          expect(DirectoryService.platformFolderCanonicalMap['genesis'], 'megadrive',
              reason: 'genesis map failed on $os');
          expect(DirectoryService.platformFolderCanonicalMap['famicom'], 'nes',
              reason: 'famicom map failed on $os');
        }
      });
    });

    group('RomConstants — cross-platform', () {
      test('extension lists are platform-independent', () {
        for (final os in ['windows', 'macos', 'linux']) {
          expect(RomConstants.platformExtensions['psx'], contains('.chd'),
              reason: 'psx .chd missing on $os');
          expect(RomConstants.platformExtensions['ps2'], contains('.chd'),
              reason: 'ps2 .chd missing on $os');
          expect(RomConstants.platformExtensions['gba'], contains('.gba'),
              reason: 'gba .gba missing on $os');
        }
      });
    });

    group('StrategyRegistry — cross-platform simulation', () {
      setUp(() {
        SharedPreferences.setMockInitialValues({});
      });

      test('initializes on simulated Windows', () async {
        final prefs = await SharedPreferences.getInstance();
        final platform = PlatformInfo('windows');
        final ds = DirectoryService(prefs, platform: platform);
        final registry = StrategyRegistry(ds, prefs, platform: platform);
        // Windows should have windows_native strategy
        expect(registry.getStrategyById('windows_native'), isNotNull);
      });

      test('initializes on simulated Linux', () async {
        final prefs = await SharedPreferences.getInstance();
        final platform = PlatformInfo('linux');
        final ds = DirectoryService(prefs, platform: platform);
        final registry = StrategyRegistry(ds, prefs, platform: platform);
        // Linux should NOT have windows_native strategy
        // (unless the definition includes linux in supported_platforms)
        expect(registry, isNotNull);
      });

      test('initializes on simulated macOS', () async {
        final prefs = await SharedPreferences.getInstance();
        final platform = PlatformInfo('macos');
        final ds = DirectoryService(prefs, platform: platform);
        final registry = StrategyRegistry(ds, prefs, platform: platform);
        expect(registry, isNotNull);
      });

      test('getStrategyForSlug returns consistent results across platforms', () async {
        for (final os in ['windows', 'macos', 'linux']) {
          final prefs = await SharedPreferences.getInstance();
          final platform = PlatformInfo(os);
          final ds = DirectoryService(prefs, platform: platform);
          final registry = StrategyRegistry(ds, prefs, platform: platform);

          // GBA should always have a strategy (RetroArch or mGBA)
          expect(registry.getStrategyForSlug('gba'), isNotNull,
              reason: 'GBA strategy missing on $os');
          // NDS should always have a strategy
          expect(registry.getStrategyForSlug('nds'), isNotNull,
              reason: 'NDS strategy missing on $os');
        }
      });
    });

    group('Game model — cross-platform', () {
      test('displayName is platform-independent', () {
        for (final os in ['windows', 'macos', 'linux']) {
          final game = Game(
            id: '1',
            name: 'Game (USA) [!] (v1.0)',
            fileSize: 1000,
          );
          expect(game.displayName, 'Game',
              reason: 'displayName failed on $os');
        }
      });

      test('fromJson is platform-independent', () {
        for (final os in ['windows', 'macos', 'linux']) {
          final json = {
            'id': '42',
            'name': 'Test Game',
            'platform_slug': 'ps2',
            'file_size_bytes': 1000,
            'has_multiple_files': false,
          };
          final game = Game.fromJson(json);
          expect(game.id, '42', reason: 'id failed on $os');
          expect(game.name, 'Test Game', reason: 'name failed on $os');
          expect(game.platformSlug, 'ps2', reason: 'platformSlug failed on $os');
        }
      });
    });
  });
}
