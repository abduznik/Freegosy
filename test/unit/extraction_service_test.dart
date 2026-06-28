import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/extraction/extraction_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ExtractionService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('extraction_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    ExtractionService createService(String platformOs) {
      SharedPreferences.setMockInitialValues({});
      // We can't easily create a DirectoryService with a fake platform here
      // since it does filesystem operations in initialize(). Use a minimal mock.
      final platform = PlatformInfo(platformOs);
      // Create a minimal ExtractionService — we only need the platform for dispatch
      return ExtractionService(_MinimalDirectoryService(), platform: platform);
    }

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

    group('cross-platform ZIP extraction', () {
      test('.zip extracts on simulated macOS', () async {
        final zipPath = await createZip({'test.txt': 'Hello!'});
        final destDir = Directory(p.join(tempDir.path, 'ext_macos'));
        await destDir.create();
        final service = createService('macos');
        await service.extract(zipPath, destDir.path);
        expect(File(p.join(destDir.path, 'test.txt')).existsSync(), isTrue);
      });

      test('.zip extracts on simulated Linux', () async {
        final zipPath = await createZip({'test.txt': 'Hello!'});
        final destDir = Directory(p.join(tempDir.path, 'ext_linux'));
        await destDir.create();
        final service = createService('linux');
        await service.extract(zipPath, destDir.path);
        expect(File(p.join(destDir.path, 'test.txt')).existsSync(), isTrue);
      });

      test('.zip extracts on simulated Windows', () async {
        final zipPath = await createZip({'test.txt': 'Hello!'});
        final destDir = Directory(p.join(tempDir.path, 'ext_windows'));
        await destDir.create();
        final service = createService('windows');
        await service.extract(zipPath, destDir.path);
        expect(File(p.join(destDir.path, 'test.txt')).existsSync(), isTrue);
      });
    });

    group('platform guards', () {
      test('.dmg throws on simulated Linux', () async {
        final dmgPath = p.join(tempDir.path, 'test.dmg');
        await File(dmgPath).writeAsBytes([0x00, 0x01]);
        final destDir = Directory(p.join(tempDir.path, 'dmg_linux'));
        await destDir.create();
        final service = createService('linux');
        expect(
          () => service.extract(dmgPath, destDir.path),
          throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('DMG extraction is only supported on macOS'),
          )),
        );
      });

      test('.dmg throws on simulated Windows', () async {
        final dmgPath = p.join(tempDir.path, 'test.dmg');
        await File(dmgPath).writeAsBytes([0x00, 0x01]);
        final destDir = Directory(p.join(tempDir.path, 'dmg_win'));
        await destDir.create();
        final service = createService('windows');
        expect(
          () => service.extract(dmgPath, destDir.path),
          throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('DMG extraction is only supported on macOS'),
          )),
        );
      });

      test('.appimage throws on simulated macOS', () async {
        final appPath = p.join(tempDir.path, 'test.AppImage');
        await File(appPath).writeAsBytes([0x7F, 0x45, 0x4C, 0x46]);
        final destDir = Directory(p.join(tempDir.path, 'app_macos'));
        await destDir.create();
        final service = createService('macos');
        expect(
          () => service.extract(appPath, destDir.path),
          throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('AppImage is only supported on Linux'),
          )),
        );
      });

      test('.appimage throws on simulated Windows', () async {
        final appPath = p.join(tempDir.path, 'test.AppImage');
        await File(appPath).writeAsBytes([0x7F, 0x45, 0x4C, 0x46]);
        final destDir = Directory(p.join(tempDir.path, 'app_win'));
        await destDir.create();
        final service = createService('windows');
        expect(
          () => service.extract(appPath, destDir.path),
          throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('AppImage is only supported on Linux'),
          )),
        );
      });
    });

    group('magic byte detection', () {
      test('unknown extension with ZIP magic extracts on all platforms', () async {
        for (final os in ['macos', 'linux', 'windows']) {
          final zipPath = await createZip({'magic.txt': 'content'});
          final renamedPath = p.join(tempDir.path, 'archive_$os.bin');
          await File(zipPath).copy(renamedPath);
          final destDir = Directory(p.join(tempDir.path, 'magic_$os'));
          await destDir.create();
          final service = createService(os);
          await service.extract(renamedPath, destDir.path);
          expect(File(p.join(destDir.path, 'magic.txt')).existsSync(), isTrue,
              reason: 'Failed on $os');
        }
      });

      test('unknown extension without ZIP magic throws on all platforms', () async {
        for (final os in ['macos', 'linux', 'windows']) {
          final fakePath = p.join(tempDir.path, 'fake_$os.bin');
          await File(fakePath).writeAsBytes([0x00, 0x01, 0x02, 0x03]);
          final destDir = Directory(p.join(tempDir.path, 'fake_$os'));
          await destDir.create();
          final service = createService(os);
          expect(
            () => service.extract(fakePath, destDir.path),
            throwsA(isA<Exception>()),
            reason: 'Should throw on $os',
          );
        }
      });
    });
  });
}

/// Minimal DirectoryService stub for ExtractionService tests.
/// Only `resolveSevenZipPath` is called by the 7z handler.
class _MinimalDirectoryService extends Fake implements DirectoryService {
  @override
  Future<String?> resolveSevenZipPath() async => null;
}
