import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/rom_constants.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Regression tests for user-reported library scanner / ROM folder issues.
///
/// Folder-name tests go through the real DirectoryService.getRomDirectory()
/// rather than a copied slug map, so they break if the production mapping
/// drifts.
void main() {
  group('Scanner extension regressions', () {
    test('Sega Saturn and Sega CD accept .chd (issue #35)', () {
      expect(DirectoryService.isRomFile('saturn', 'Panzer Dragoon Saga (Disc 1).chd'), isTrue);
      expect(DirectoryService.isRomFile('segacd', 'Sonic CD (USA).chd'), isTrue);
    });

    test('Sega Master System accepts .7z under both slugs (issue #36)', () {
      expect(DirectoryService.isRomFile('sms', 'Alex Kidd in Miracle World (USA).7z'), isTrue);
      expect(DirectoryService.isRomFile('mastersystem', 'Alex Kidd in Miracle World (USA).7z'), isTrue);
    });

    test('Arcade and MAME accept .zip (issue #37)', () {
      expect(DirectoryService.isRomFile('arcade', 'sf2.zip'), isTrue);
      expect(DirectoryService.isRomFile('mame', 'sf2.zip'), isTrue);
    });

    test('every Neo Geo slug variant accepts .zip (issue #58)', () {
      const variants = [
        'neogeo', 'neo-geo', 'neogeoaes', 'neogeomvs',
        'neo-geo-aes', 'neo-geo-mvs', 'mvs', 'aes',
      ];
      for (final slug in variants) {
        expect(DirectoryService.isRomFile(slug, 'mslug.zip'), isTrue,
            reason: 'Neo Geo slug "$slug" should accept .zip');
      }
    });

    test('Famicom Disk System accepts .fds under both slugs (issue #57)', () {
      expect(DirectoryService.isRomFile('fds', 'Zelda no Densetsu (Japan).fds'), isTrue);
      expect(DirectoryService.isRomFile('famicom-disk-system', 'Zelda no Densetsu (Japan).fds'), isTrue);
    });

    test('GameCube and Wii accept .m3u playlists (issue #54)', () {
      expect(DirectoryService.isRomFile('gc', 'Tales of Symphonia (USA).m3u'), isTrue);
      expect(DirectoryService.isRomFile('gamecube', 'Tales of Symphonia (USA).m3u'), isTrue);
      expect(DirectoryService.isRomFile('wii', 'Game.m3u'), isTrue);
    });

    test('extension matching is case-insensitive for uppercase .ZIP/.CHD', () {
      expect(DirectoryService.isRomFile('arcade', 'SF2.ZIP'), isTrue);
      expect(DirectoryService.isRomFile('saturn', 'GAME.CHD'), isTrue);
    });

    test('every extension in platformExtensions starts with a dot and is lowercase', () {
      // isRomFile compares against p.extension(), which always includes the
      // leading dot — an entry like "chd" or ".CHD" would silently never match.
      for (final entry in RomConstants.platformExtensions.entries) {
        for (final ext in entry.value) {
          expect(ext.startsWith('.'), isTrue,
              reason: '"${entry.key}" extension "$ext" is missing its leading dot');
          expect(ext, ext.toLowerCase(),
              reason: '"${entry.key}" extension "$ext" must be lowercase');
        }
      }
    });
  });

  group('ROM folder resolution regressions (real DirectoryService)', () {
    late Directory tempDir;
    late DirectoryService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('scanner_regression_test');
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      service = DirectoryService(prefs);
      service.romsRootPath = tempDir.path;
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<String> folderFor(String slug) async {
      final game = Game(id: '1', name: 'Test', platformSlug: slug, fileSize: 0);
      return p.basename(await service.getRomDirectory(game));
    }

    test('genesis downloads land in the megadrive folder (issue #38)', () async {
      expect(await folderFor('genesis'), 'megadrive');
      expect(await folderFor('megadrive'), 'megadrive');
    });

    test('genesis downloads land in megadrive under the EmuDeck preset (issue #38)', () async {
      service.linuxSyncPreset = 'emudeck';
      expect(await folderFor('genesis'), 'megadrive');
    });

    test('3DS slug variants resolve to n3ds under the EmuDeck preset (issue #34)', () async {
      service.linuxSyncPreset = 'emudeck';
      for (final slug in ['3ds', 'nintendo-3ds', 'new-nintendo-3ds']) {
        expect(await folderFor(slug), 'n3ds', reason: 'slug "$slug"');
      }
    });

    test('every Neo Geo slug variant shares one folder (issue #58)', () async {
      for (final slug in ['neogeo', 'neo-geo', 'neogeoaes', 'neogeomvs', 'neo-geo-aes', 'neo-geo-mvs', 'mvs', 'aes']) {
        expect(await folderFor(slug), 'neogeo', reason: 'slug "$slug"');
      }
    });

    test('Famicom Disk System gets its own fds folder, not nes (issue #57)', () async {
      expect(await folderFor('famicom-disk-system'), 'fds');
      expect(await folderFor('fds'), 'fds');
    });

    test('an existing raw-slug folder is kept for backwards compatibility', () async {
      // Users who downloaded before canonicalisation have ROMs under the raw
      // slug; switching them to a new empty folder would hide their library.
      await Directory(p.join(tempDir.path, 'genesis')).create();
      expect(await folderFor('genesis'), 'genesis');
    });
  });
}
