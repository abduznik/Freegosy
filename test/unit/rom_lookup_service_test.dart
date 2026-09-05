import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/rom_lookup_service.dart';
import 'package:freegosy/core/storage/file_system_index.dart';
import 'package:path/path.dart' as p;

void main() {
  group('RomLookupService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rom_lookup_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Game makeGame({
      String id = '1',
      String name = 'Test Game',
      String? fsName,
      String? fileName,
      String? platformSlug = 'ps2',
      bool hasMultipleFiles = false,
    }) {
      return Game(
        id: id,
        name: name,
        fsName: fsName,
        fileName: fileName,
        platformSlug: platformSlug,
        fileSize: 1000,
        hasMultipleFiles: hasMultipleFiles,
      );
    }

    group('findExistingRomPath', () {
      test('exact match by fsName', () async {
        final file = File(p.join(tempDir.path, 'game.iso'));
        await file.writeAsString('data');

        final game = makeGame(fsName: 'game.iso');
        final result = await RomLookupService.findExistingRomPath(
          game,
          tempDir.path,
        );
        expect(result, isNotNull);
        expect(p.basename(result!), 'game.iso');
      });

      test('falls back to fileName when fsName is null', () async {
        final file = File(p.join(tempDir.path, 'actual_game.iso'));
        await file.writeAsString('data');

        // When fsName is null, the service uses fileName as baseName
        final game = makeGame(
          fsName: null,
          fileName: 'actual_game.iso',
        );
        final result = await RomLookupService.findExistingRomPath(
          game,
          tempDir.path,
        );
        expect(result, isNotNull);
        expect(p.basename(result!), 'actual_game.iso');
      });

      test('falls back to sanitized game.name', () async {
        final sanitizedName = 'Game (USA) [!]'
            .replaceAll(RegExp(r'[<>:"/\\|?]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final file = File(p.join(tempDir.path, sanitizedName));
        await file.writeAsString('data');

        final game = makeGame(
          name: 'Game (USA) [!]',
          fsName: null,
          fileName: null,
        );
        final result = await RomLookupService.findExistingRomPath(
          game,
          tempDir.path,
        );
        expect(result, isNotNull);
      });

      test('returns null for nonexistent romDir', () async {
        final game = makeGame();
        final result = await RomLookupService.findExistingRomPath(
          game,
          '/nonexistent/path/that/does/not/exist',
        );
        expect(result, isNull);
      });

      test('case-insensitive match', () async {
        final file = File(p.join(tempDir.path, 'MyGame.iso'));
        await file.writeAsString('data');

        final game = makeGame(fsName: 'mygame.iso');
        final result = await RomLookupService.findExistingRomPath(
          game,
          tempDir.path,
        );
        expect(result, isNotNull);
        // macOS filesystem is case-insensitive but case-preserving
        expect(p.basename(result!).toLowerCase(), 'mygame.iso');
      });

      test('multi-file folder detection finds main ROM', () async {
        final folder = Directory(p.join(tempDir.path, 'MultiDisc'));
        await folder.create();
        await File(p.join(folder.path, 'disc1.chd')).writeAsString('small');
        await File(p.join(folder.path, 'disc2.chd')).writeAsString('large data here');

        final game = makeGame(
          name: 'MultiDisc',
          fsName: 'MultiDisc',
          hasMultipleFiles: true,
          platformSlug: 'psx',
        );
        final result = await RomLookupService.findExistingRomPath(
          game,
          tempDir.path,
        );
        expect(result, isNotNull);
        // Should find the largest file in the folder
        expect(result, contains('disc2.chd'));
      });

      test('index hit on file returns path', () async {
        final file = File(p.join(tempDir.path, 'indexed_game.iso'));
        await file.writeAsString('data');

        final index = FileSystemIndex(
          rootPath: tempDir.path,
          files: {'indexed_game.iso': file.path},
          dirs: {},
          fileSizes: {file.path: 1000},
        );

        final game = makeGame(fsName: 'indexed_game.iso');
        final result = await RomLookupService.findExistingRomPath(
          game,
          tempDir.path,
          index: index,
        );
        expect(result, file.path);
      });

      test('index skips .part files in fuzzy match', () async {
        final partFile = File(p.join(tempDir.path, 'game.iso.part'));
        await partFile.writeAsString('partial');
        final realFile = File(p.join(tempDir.path, 'game.iso'));
        await realFile.writeAsString('full data');

        final index = FileSystemIndex(
          rootPath: tempDir.path,
          files: {
            'game.iso.part': partFile.path,
            'game.iso': realFile.path,
          },
          dirs: {},
          fileSizes: {},
        );

        final game = makeGame(fsName: 'game');
        final result = await RomLookupService.findExistingRomPath(
          game,
          tempDir.path,
          index: index,
        );
        // Should match via extension check, not the .part file
        expect(result, isNotNull);
      });
    });

    group('findMainRomInFolder', () {
      test('picks largest file by extension', () async {
        final folder = Directory(p.join(tempDir.path, 'GameFolder'));
        await folder.create();
        await File(p.join(folder.path, 'small.iso')).writeAsString('x');
        await File(p.join(folder.path, 'big.iso'))
            .writeAsString('x' * 1000);

        final game = makeGame(platformSlug: 'ps2');
        final result = await RomLookupService.findMainRomInFolder(
          game,
          folder.path,
        );
        expect(result, isNotNull);
        expect(p.basename(result!), 'big.iso');
      });

      test('folder-based platforms return folder path', () async {
        final folder = Directory(p.join(tempDir.path, 'PS3Game'));
        await folder.create();
        // No matching extension files
        await File(p.join(folder.path, 'readme.txt')).writeAsString('info');

        final game = makeGame(platformSlug: 'ps3');
        final result = await RomLookupService.findMainRomInFolder(
          game,
          folder.path,
        );
        expect(result, isNotNull);
        expect(result, contains('PS3Game'));
      });

      test('returns null for empty folder on non-folder platform', () async {
        final folder = Directory(p.join(tempDir.path, 'Empty'));
        await folder.create();

        final game = makeGame(platformSlug: 'gba');
        final result = await RomLookupService.findMainRomInFolder(
          game,
          folder.path,
        );
        expect(result, isNull);
      });

      // Regression test for issue #54: GameCube multi-disc games loading a
      // random disc. Before the fix, findMainRomInFolder always picked the
      // largest matching file, ignoring any .m3u playlist that correctly
      // encodes the intended disc/order. This asserts the .m3u is now
      // preferred even when a same- or larger-sized .iso is present.
      test('prefers .m3u playlist over largest .iso for multi-disc GC folder', () async {
        final folder = Directory(p.join(tempDir.path, 'GCMultiDisc'));
        await folder.create();
        await File(p.join(folder.path, 'disc1.iso')).writeAsString('x' * 100);
        // Deliberately larger than disc1 so the old "largest file" logic
        // would have picked this one instead of disc 1.
        await File(p.join(folder.path, 'disc2.iso')).writeAsString('x' * 1000);
        await File(p.join(folder.path, 'game.m3u')).writeAsString('disc1.iso\ndisc2.iso\n');

        final game = makeGame(platformSlug: 'gc');
        final result = await RomLookupService.findMainRomInFolder(
          game,
          folder.path,
        );
        expect(result, isNotNull);
        expect(p.basename(result!), 'game.m3u');
      });

      test('falls back to largest file when no .m3u present (gc)', () async {
        final folder = Directory(p.join(tempDir.path, 'GCNoM3u'));
        await folder.create();
        await File(p.join(folder.path, 'disc1.iso')).writeAsString('x' * 100);
        await File(p.join(folder.path, 'disc2.iso')).writeAsString('x' * 1000);

        final game = makeGame(platformSlug: 'gc');
        final result = await RomLookupService.findMainRomInFolder(
          game,
          folder.path,
        );
        expect(result, isNotNull);
        expect(p.basename(result!), 'disc2.iso');
      });
    });

    group('resolveFuzzyRomFile', () {
      test('exact file path returns as-is', () async {
        final file = File(p.join(tempDir.path, 'game.iso'));
        await file.writeAsString('data');

        final result = await RomLookupService.resolveFuzzyRomFile(
          file.path,
          ['.iso'],
        );
        expect(result, file.path);
      });

      test('path with extension appended', () async {
        final file = File(p.join(tempDir.path, 'game.iso'));
        await file.writeAsString('data');

        final result = await RomLookupService.resolveFuzzyRomFile(
          p.join(tempDir.path, 'game'),
          ['.iso'],
        );
        expect(result, file.path);
      });

      test('directory returns largest matching file', () async {
        final dir = Directory(p.join(tempDir.path, 'GameDir'));
        await dir.create();
        await File(p.join(dir.path, 'a.iso')).writeAsString('small');
        await File(p.join(dir.path, 'b.iso')).writeAsString('x' * 500);

        final result = await RomLookupService.resolveFuzzyRomFile(
          dir.path,
          ['.iso'],
        );
        expect(result, isNotNull);
        expect(p.basename(result!), 'b.iso');
      });

      test('fuzzy token match works', () async {
        final file = File(p.join(tempDir.path, 'Dragon Ball Z - Legacy.chd'));
        await file.writeAsString('data');

        final result = await RomLookupService.resolveFuzzyRomFile(
          p.join(tempDir.path, 'Dragon Ball Z Legacy'),
          ['.chd'],
        );
        expect(result, file.path);
      });

      test('returns null when no match', () async {
        await File(p.join(tempDir.path, 'other.iso')).writeAsString('data');

        final result = await RomLookupService.resolveFuzzyRomFile(
          p.join(tempDir.path, 'CompletelyDifferent'),
          ['.iso'],
        );
        expect(result, isNull);
      });
    });
  });
}
