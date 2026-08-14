import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/rom_constants.dart';

void main() {
  group('EmuDeck n3ds folder edge case', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('freegosy_n3ds_test_');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('DirectoryService.getRomDirectory', () {
      Future<DirectoryService> createService(String preset) async {
        final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
        final service = DirectoryService(prefs);
        service.romsRootPath = tempDir.path;
        service.linuxSyncPreset = preset;
        return service;
      }

      test('maps 3ds platformSlug to n3ds folder on EmuDeck preset', () async {
        final service = await createService('emudeck');
        await Directory(p.join(tempDir.path, 'n3ds')).create(recursive: true);

        final game = Game(id: '1', name: 'Test', platformSlug: '3ds', fileSize: 0);
        final romDir = await service.getRomDirectory(game);

        expect(romDir, p.join(tempDir.path, 'n3ds'));
      });

      test('maps all 3DS slug variants to n3ds folder on EmuDeck', () async {
        final service = await createService('emudeck');
        await Directory(p.join(tempDir.path, 'n3ds')).create(recursive: true);

        final slugs = ['3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl'];
        for (final slug in slugs) {
          final game = Game(id: 'x', name: 'Test', platformSlug: slug, fileSize: 0);
          final romDir = await service.getRomDirectory(game);
          expect(romDir, p.join(tempDir.path, 'n3ds'), reason: 'slug "$slug" should map to n3ds');
        }
      });

      test('uses slug directly as folder name on default preset', () async {
        final service = await createService('default');

        final game = Game(id: '1', name: 'Test', platformSlug: '3ds', fileSize: 0);
        final romDir = await service.getRomDirectory(game);

        expect(romDir, p.join(tempDir.path, '3ds'));
      });
    });

    group('DirectoryService.findExistingRomPath on EmuDeck', () {
      test('finds 3ds game in n3ds folder on EmuDeck preset', () async {
        final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
        final service = DirectoryService(prefs);
        service.romsRootPath = tempDir.path;
        service.linuxSyncPreset = 'emudeck';

        await Directory(p.join(tempDir.path, 'n3ds')).create(recursive: true);
        final romFile = File(p.join(tempDir.path, 'n3ds', 'TestGame.3ds'));
        await romFile.writeAsString('fake rom');

        final game = Game(
          id: '1',
          name: 'TestGame',
          platformSlug: '3ds',
          fileName: 'TestGame.3ds',
          fsName: 'TestGame.3ds',
          fileSize: 100,
        );

        final foundPath = await service.findExistingRomPath(game);

        expect(foundPath, isNotNull);
        expect(foundPath, endsWith(p.join('n3ds', 'TestGame.3ds')));
      });

      test('finds all 3DS slug variant games in n3ds folder on EmuDeck', () async {
        final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
        final service = DirectoryService(prefs);
        service.romsRootPath = tempDir.path;
        service.linuxSyncPreset = 'emudeck';

        await Directory(p.join(tempDir.path, 'n3ds')).create(recursive: true);

        final slugs = ['3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl'];
        for (int i = 0; i < slugs.length; i++) {
          final romFile = File(p.join(tempDir.path, 'n3ds', 'Game$i.3ds'));
          await romFile.writeAsString('fake rom $i');

          final game = Game(
            id: '$i',
            name: 'Game$i',
            platformSlug: slugs[i],
            fileName: 'Game$i.3ds',
            fsName: 'Game$i.3ds',
            fileSize: 100,
          );

          final foundPath = await service.findExistingRomPath(game);
          expect(foundPath, isNotNull, reason: 'slug "${slugs[i]}" should find game in n3ds');
          expect(foundPath, endsWith(p.join('n3ds', 'Game$i.3ds')));
        }
      });
    });

    group('Scanner folder alias map', () {
      test('exposes platformFolderCanonicalMap for scanner reverse lookup', () {
        expect(DirectoryService.platformFolderCanonicalMap['n3ds'], equals('3ds'));
        expect(DirectoryService.platformFolderCanonicalMap['nintendo-3ds'], equals('3ds'));
        expect(DirectoryService.platformFolderCanonicalMap['nintendo3ds'], equals('3ds'));
        expect(DirectoryService.platformFolderCanonicalMap['new-nintendo-3ds'], equals('3ds'));
        expect(DirectoryService.platformFolderCanonicalMap['new-nintendo-3ds-xl'], equals('3ds'));
        expect(DirectoryService.platformFolderCanonicalMap['3ds'], isNull);
      });
    });

    group('RomConstants platformExtensions for n3ds', () {
      test('includes n3ds as a known platform extension key', () {
        final extensions = RomConstants.platformExtensions['n3ds'];
        expect(extensions, isNotNull);
        expect(extensions!.contains('.3ds'), isTrue);
        expect(extensions.contains('.cia'), isTrue);
        expect(extensions.contains('.app'), isTrue);
      });

      test('includes all 3DS variant extension keys', () {
        for (final slug in ['n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl']) {
          final extensions = RomConstants.platformExtensions[slug];
          expect(extensions, isNotNull, reason: 'slug "$slug" should have extension entries');
          expect(extensions!.contains('.3ds'), isTrue, reason: 'slug "$slug" missing .3ds');
          expect(extensions.contains('.cia'), isTrue, reason: 'slug "$slug" missing .cia');
          expect(extensions.contains('.app'), isTrue, reason: 'slug "$slug" missing .app');
        }
      });
    });
  });
}
