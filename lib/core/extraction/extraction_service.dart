import 'dart:io';
import 'package:archive/archive_io.dart';
import '../storage/directory_service.dart';

class ExtractionService {
  final DirectoryService directoryService;

  ExtractionService(this.directoryService);

  Future<void> extract(String archivePath, String destDir) async {
    final pathLower = archivePath.toLowerCase();

    if (pathLower.endsWith('.zip')) {
      final bytes = await File(archivePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      extractArchiveToDisk(archive, destDir);
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
    } else {
      throw Exception('Unsupported archive format: $archivePath');
    }
  }
}
