import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/extraction/extraction_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ExtractionService', () {
    late ExtractionService service;
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dirService = DirectoryService(prefs);
      service = ExtractionService(dirService);
      tempDir = await Directory.systemTemp.createTemp('extraction_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// Creates a ZIP file containing [files] map of {filename: content}.
    Future<String> createZip(Map<String, String> files) async {
      final zipPath = p.join(tempDir.path, 'test_archive.zip');
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      for (final entry in files.entries) {
        final file = File(p.join(tempDir.path, entry.key));
        await file.writeAsString(entry.value);
        await encoder.addFile(file, entry.key);
      }
      encoder.close();
      return zipPath;
    }

    test('.zip extracts files correctly', () async {
      final zipPath = await createZip({
        'test.txt': 'Hello, World!',
      });

      final destDir = Directory(p.join(tempDir.path, 'extracted'));
      await destDir.create();

      await service.extract(zipPath, destDir.path);

      expect(File(p.join(destDir.path, 'test.txt')).existsSync(), isTrue);
      expect(
          await File(p.join(destDir.path, 'test.txt')).readAsString(),
          'Hello, World!');
    });

    test('unknown extension with ZIP magic bytes extracts', () async {
      // Create a ZIP but rename it to .bin
      final zipPath = await createZip({'magic.txt': 'magic content'});
      final renamedPath = p.join(tempDir.path, 'archive.bin');
      await File(zipPath).rename(renamedPath);

      final destDir = Directory(p.join(tempDir.path, 'extracted_magic'));
      await destDir.create();

      await service.extract(renamedPath, destDir.path);

      expect(
          File(p.join(destDir.path, 'magic.txt')).existsSync(), isTrue);
    });

    test('unknown extension without ZIP magic throws', () async {
      final fakePath = p.join(tempDir.path, 'not_archive.bin');
      await File(fakePath).writeAsBytes([0x00, 0x01, 0x02, 0x03]);

      final destDir = Directory(p.join(tempDir.path, 'extracted_fail'));
      await destDir.create();

      expect(
        () => service.extract(fakePath, destDir.path),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Unsupported archive format'),
        )),
      );
    });

    test('.dmg on non-macOS throws', () async {
      if (Platform.isMacOS) {
        // Skip on macOS — the test is for non-macOS behavior
        return;
      }

      final dmgPath = p.join(tempDir.path, 'test.dmg');
      await File(dmgPath).writeAsBytes([0x00, 0x01]);

      final destDir = Directory(p.join(tempDir.path, 'extracted_dmg'));
      await destDir.create();

      expect(
        () => service.extract(dmgPath, destDir.path),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('DMG extraction is only supported on macOS'),
        )),
      );
    });

    test('.appimage on non-Linux throws', () async {
      if (Platform.isLinux) {
        // Skip on Linux — the test is for non-Linux behavior
        return;
      }

      final appPath = p.join(tempDir.path, 'test.AppImage');
      await File(appPath).writeAsBytes([0x7F, 0x45, 0x4C, 0x46]);

      final destDir = Directory(p.join(tempDir.path, 'extracted_app'));
      await destDir.create();

      expect(
        () => service.extract(appPath, destDir.path),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('AppImage is only supported on Linux'),
        )),
      );
    });
  });
}
