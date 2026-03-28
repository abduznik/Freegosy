import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import '../storage/directory_service.dart';

Future<void> _extractZipIsolate(List<dynamic> args) async {
  final bytes = args[0] as Uint8List;
  final destDir = args[1] as String;
  final archive = ZipDecoder().decodeBytes(bytes);
  extractArchiveToDisk(archive, destDir);
}

class ExtractionService {
  final DirectoryService directoryService;

  ExtractionService(this.directoryService);

  Future<void> extract(String archivePath, String destDir) async {
    final pathLower = archivePath.toLowerCase();

    if (pathLower.endsWith('.dmg')) {
      final mountResult = await Process.run(
        'hdiutil',
        ['attach', archivePath, '-nobrowse', '-readonly'],
      );
      if (mountResult.exitCode != 0) {
        throw Exception('Failed to mount DMG: ${mountResult.stderr}');
      }

      String? mountPoint;
      for (final line in mountResult.stdout.toString().split('\n')) {
        if (line.contains('/Volumes/')) {
          mountPoint = line.trim().split('\t').last.trim();
          break;
        }
      }
      if (mountPoint == null) {
        throw Exception('Could not determine DMG mount point');
      }

      try {
        final volume = Directory(mountPoint);
        await for (final entity in volume.list()) {
          if (entity is Directory && entity.path.endsWith('.app')) {
            final appName = entity.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last;
            final dest = Directory('$destDir/$appName');
            await _copyDirectory(entity, dest);
            break;
          }
        }
      } finally {
        await Process.run('hdiutil', ['detach', mountPoint, '-force']);
      }
      return;
    }

    if (pathLower.endsWith('.zip')) {
      if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run(
          'unzip',
          ['-o', archivePath, '-d', destDir],
          runInShell: false,
        );
        if (result.exitCode != 0) {
          throw Exception('unzip failed: ${result.stderr}');
        }
        await Process.run(
          'find',
          [destDir, '-name', '*.app', '-exec', 'chmod', '-R', '+x', '{}', ';'],
          runInShell: false,
        );
        // Remove quarantine and self-sign all .app bundles so macOS allows launch
        final findResult = await Process.run(
          'find', [destDir, '-name', '*.app', '-maxdepth', '3'],
          runInShell: false,
        );
        for (final appPath in findResult.stdout.toString().trim().split('\n')) {
          if (appPath.isEmpty) continue;
          await Process.run('xattr', ['-rd', 'com.apple.quarantine', appPath]);
          await Process.run('codesign', ['--force', '--deep', '--sign', '-', appPath]);
        }
      } else {
        final fileBytes = await File(archivePath).readAsBytes();
        await compute(_extractZipIsolate, [fileBytes, destDir]);
      }
    } else if (pathLower.endsWith('.7z')) {
      final sevenZipExe = await directoryService.resolveSevenZipPath();
      if (sevenZipExe == null) {
        throw Exception('7zr.exe could not be initialized. Try reinstalling Freegosy.');
      }
      final result = await Process.run(
        sevenZipExe,
        ['x', archivePath, '-o$destDir', '-y'],
        runInShell: false,
      );
      if (result.exitCode != 0) {
        throw Exception('7z extraction failed: ${result.stderr}');
      }
    } else if (pathLower.endsWith('.exe')) {
      var result = await Process.run(
        archivePath,
        ['-o$destDir', '-y'],
        runInShell: false,
      );
      if (result.exitCode != 0) {
        result = await Process.run(
          archivePath,
          [],
          workingDirectory: destDir,
        );
      }
    } else {
      bool isZip = false;
      try {
        final raf = await File(archivePath).open();
        final header = await raf.read(4);
        await raf.close();
        isZip = header.length >= 2 && header[0] == 0x50 && header[1] == 0x4B;
      } catch (_) {}

      if (isZip) {
        if (Platform.isMacOS || Platform.isLinux) {
          final result = await Process.run(
            'unzip',
            ['-o', archivePath, '-d', destDir],
            runInShell: false,
          );
          if (result.exitCode != 0) {
            throw Exception('unzip failed: ${result.stderr}');
          }
        } else {
          final fileBytes = await File(archivePath).readAsBytes();
          await compute(_extractZipIsolate, [fileBytes, destDir]);
        }
      } else {
        throw Exception('Unsupported archive format: $archivePath');
      }
    }
  }

  Future<void> _copyDirectory(Directory source, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = entity.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;
      if (entity is Directory) {
        await _copyDirectory(entity, Directory('${dest.path}/$name'));
      } else if (entity is File) {
        await entity.copy('${dest.path}/$name');
      }
    }
  }
}
