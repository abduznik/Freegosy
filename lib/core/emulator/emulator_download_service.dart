import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import '../downloader/download_service.dart';
import '../storage/directory_service.dart';
import 'emulator_registry_data.dart';

class EmulatorDownloadService {
  final Dio _dio;
  final DirectoryService _directoryService;

  EmulatorDownloadService(this._dio, this._directoryService);

  Stream<DownloadProgress> downloadEmulator(String emulatorId) async* {
    final definition = kEmulatorDefinitions.firstWhere(
      (d) => d['id'] == emulatorId,
      orElse: () => {},
    );

    if (definition.isEmpty) {
      yield DownloadProgress(id: emulatorId, error: 'Emulator definition not found');
      return;
    }

    final String? downloadUrl = Platform.isWindows
        ? definition['windows_url'] as String?
        : definition['linux_url'] as String?;

    if (downloadUrl == null) {
      yield DownloadProgress(id: emulatorId, error: 'No download URL for this platform');
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final fileName = p.basename(downloadUrl);
    final tempFilePath = p.join(tempDir.path, fileName);
    final emulatorDir = await _directoryService.getEmulatorDirectory(emulatorId);

    final controller = StreamController<DownloadProgress>();

    try {
      _dio.download(
        downloadUrl,
        tempFilePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            controller.add(DownloadProgress(
              id: emulatorId,
              percent: received / total,
              bytesReceived: received,
              totalBytes: total,
            ));
          }
        },
        deleteOnError: true,
      ).then((_) async {
        try {
          await _extractArchive(tempFilePath, emulatorDir);
          controller.add(DownloadProgress(
            id: emulatorId,
            percent: 1.0,
            isComplete: true,
          ));
        } catch (e) {
          controller.add(DownloadProgress(id: emulatorId, error: 'Extraction failed: $e'));
        } finally {
          controller.close();
          final f = File(tempFilePath);
          if (await f.exists()) await f.delete();
        }
      }).catchError((e) {
        controller.add(DownloadProgress(id: emulatorId, error: 'Download failed: $e'));
        controller.close();
      });

      yield* controller.stream;
    } catch (e) {
      yield DownloadProgress(id: emulatorId, error: 'Error: $e');
    }
  }

  Future<void> _extractArchive(String archivePath, String destDir) async {
    if (archivePath.endsWith('.zip')) {
      final bytes = await File(archivePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      extractArchiveToDisk(archive, destDir);
    } else if (archivePath.endsWith('.7z')) {
      final result = await Process.run(
        '7z', ['x', archivePath, '-o$destDir', '-y'],
        runInShell: true,
      );
      if (result.exitCode != 0) {
        throw Exception('7z extraction failed: ${result.stderr}');
      }
    } else {
      throw Exception('Unsupported archive format: $archivePath');
    }
  }
}
