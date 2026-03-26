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

    if (pathLower.endsWith('.zip')) {
      final fileBytes = await File(archivePath).readAsBytes();
      await compute(_extractZipIsolate, [fileBytes, destDir]);
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
      // Self-extracting archive
      var result = await Process.run(
        archivePath,
        ['-o$destDir', '-y'],
        runInShell: false,
      );
      if (result.exitCode != 0) {
        // Try as a plain self-extractor with no arguments
        result = await Process.run(
          archivePath,
          [],
          workingDirectory: destDir,
        );
      }
    } else {
      // Try ZIP magic bytes (PK = 0x50 0x4B)
      bool isZip = false;
      try {
        final raf = await File(archivePath).open();
        final header = await raf.read(4);
        await raf.close();
        isZip = header.length >= 2 && header[0] == 0x50 && header[1] == 0x4B;
      } catch (_) {}

      if (isZip) {
        final fileBytes = await File(archivePath).readAsBytes();
        await compute(_extractZipIsolate, [fileBytes, destDir]);
      } else {
        throw Exception('Unsupported archive format: $archivePath');
      }
    }
  }
}
