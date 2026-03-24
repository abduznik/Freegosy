import 'package:dio/dio.dart';
import 'dart:async';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/rendering.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';

class DownloadProgress {
  final String id;
  final String gameName;
  final double percent;
  final int bytesReceived;
  final int totalBytes;
  final bool isComplete;
  final String? error;
  final String status; // 'downloading', 'extracting', 'complete', 'error'

  DownloadProgress({
    required this.id,
    required this.gameName,
    this.percent = 0.0,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.isComplete = false,
    this.error,
    this.status = 'Downloading...',
  });
}

class DownloadService {
  final Dio dio;
  final DirectoryService directoryService;

  DownloadService({required this.dio, required this.directoryService});

  Stream<DownloadProgress> download(Game game, String downloadUrl, {Map<String, String>? headers}) async* {
    if (await directoryService.isRomDownloaded(game)) {
      yield DownloadProgress(id: game.id, gameName: game.name, percent: 1.0, isComplete: true);
      return;
    }

    final savePath = await directoryService.getRomFilePath(game);
    final saveFile = File(savePath);
    await saveFile.parent.create(recursive: true);

    final controller = StreamController<DownloadProgress>();

    try {
      dio.download(
        downloadUrl,
        savePath,
        options: Options(headers: headers),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            controller.add(DownloadProgress(
              id: game.id,
              gameName: game.name,
              percent: received / total,
              bytesReceived: received,
              totalBytes: total,
            ));
          }
        },
        deleteOnError: true,
      ).then((_) async {
        try {
          final isWindowsGame = ['windows', 'pc', 'win'].contains(game.platformSlug?.toLowerCase() ?? '');
          final isArchive = savePath.toLowerCase().endsWith('.zip') ||
              savePath.toLowerCase().endsWith('.7z');
          if (game.isMultiFile || (isWindowsGame && isArchive)) {
            controller.add(DownloadProgress(
              id: game.id,
              gameName: game.name,
              percent: 1.0,
              status: 'Extracting...',
            ));
            await _extractMultiFile(game, savePath);
          }
          controller.add(DownloadProgress(
            id: game.id,
            gameName: game.name,
            percent: 1.0,
            isComplete: true,
            status: 'Done!',
          ));
        } catch (e) {
          controller.add(DownloadProgress(
            id: game.id,
            gameName: game.name,
            error: 'Extraction failed: $e',
          ));
        } finally {
          controller.close();
        }
      }).catchError((e) {
        controller.add(DownloadProgress(id: game.id, gameName: game.name, error: 'Download failed: $e'));
        controller.close();
      });

      yield* controller.stream;
    } catch (e) {
      yield DownloadProgress(id: game.id, gameName: game.name, error: 'Error: $e');
      if (await saveFile.exists()) await saveFile.delete();
    }
  }

  /// Extracts a multi-file zip into a folder named after the game,
  /// then deletes the zip. Finds the main ROM by largest file size.
  Future<void> _extractMultiFile(Game game, String zipPath) async {
    final romDir = await directoryService.getRomDirectory(game);
    // Sanitize game name for use as folder name
    final folderName = game.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final extractDir = '$romDir/$folderName';

    await Directory(extractDir).create(recursive: true);

    if (zipPath.toLowerCase().endsWith('.7z')) {
      final sevenZipExe = await directoryService.resolveSevenZipPath();
      if (sevenZipExe == null) {
        throw Exception('7zr.exe could not be initialized. Try reinstalling Freegosy.');
      }
      final result = await Process.run(
        sevenZipExe, ['x', zipPath, '-o$extractDir', '-y'],
        runInShell: false,
      );
      if (result.exitCode != 0) {
        throw Exception('7z extraction failed: ${result.stderr}');
      }
    } else {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      extractArchiveToDisk(archive, extractDir);
    }

    // Delete the archive after extraction
    await File(zipPath).delete();

    // Log the largest file found (main ROM)
    File? largestFile;
    int largestSize = 0;
    await for (final entity in Directory(extractDir).list(recursive: true)) {
      if (entity is File) {
        final size = await entity.length();
        if (size > largestSize) {
          largestSize = size;
          largestFile = entity;
        }
      }
    }
    debugPrint('[DownloadService] multi-file extracted to $extractDir, main ROM: ${largestFile?.path}');
  }
}