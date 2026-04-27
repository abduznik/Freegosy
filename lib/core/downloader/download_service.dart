import 'package:dio/dio.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/extraction/extraction_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';

class DownloadProgress {
  final String id;
  final String gameName;
  final double percent;
  final int bytesReceived;
  final int totalBytes;
  final bool isComplete;
  final bool isPaused;
  final String? error;
  final String status; // 'downloading', 'extracting', 'complete', 'error', 'paused', 'canceled'
  final Game? game;
  final String? downloadUrl;

  DownloadProgress({
    required this.id,
    required this.gameName,
    this.percent = 0.0,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.isComplete = false,
    this.isPaused = false,
    this.error,
    this.status = 'Downloading...',
    this.game,
    this.downloadUrl,
  });

  DownloadProgress copyWith({
    double? percent,
    int? bytesReceived,
    int? totalBytes,
    bool? isComplete,
    bool? isPaused,
    String? error,
    String? status,
    Game? game,
    String? downloadUrl,
  }) {
    return DownloadProgress(
      id: id,
      gameName: gameName,
      percent: percent ?? this.percent,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      totalBytes: totalBytes ?? this.totalBytes,
      isComplete: isComplete ?? this.isComplete,
      isPaused: isPaused ?? this.isPaused,
      error: error ?? this.error,
      status: status ?? this.status,
      game: game ?? this.game,
      downloadUrl: downloadUrl ?? this.downloadUrl,
    );
  }
}

class DownloadService {
  final Dio dio;
  final DirectoryService directoryService;
  final ExtractionService extractionService;

  DownloadService({
    required this.dio,
    required this.directoryService,
    required this.extractionService,
  });

  Stream<DownloadProgress> download(Game game, String downloadUrl, {Map<String, String>? headers, CancelToken? cancelToken}) async* {
    if (await directoryService.isRomDownloaded(game)) {
      yield DownloadProgress(id: game.id, gameName: game.name, percent: 1.0, isComplete: true);
      return;
    }

    final finalPath = await directoryService.getRomFilePath(game);
    final partPath = '$finalPath.part';
    final partFile = File(partPath);
    await partFile.parent.create(recursive: true);

    int existingBytes = 0;
    if (await partFile.exists()) {
      existingBytes = await partFile.length();
    }

    yield DownloadProgress(
      id: game.id,
      gameName: game.name,
      percent: 0.0,
      bytesReceived: existingBytes,
      status: 'Starting...',
    );

    debugPrint("[DownloadService] Starting download for: ${game.name}");
    debugPrint("[DownloadService] URL: $downloadUrl");
    debugPrint("[DownloadService] Final Path: $finalPath");
    debugPrint("[DownloadService] Part Path: $partPath");
    debugPrint("[DownloadService] Existing Bytes: $existingBytes");

    try {
      final options = Options(
        headers: {
          ...?headers,
          if (existingBytes > 0) 'Range': 'bytes=$existingBytes-',
        },
        responseType: ResponseType.stream,
      );

      final response = await dio.get(downloadUrl, options: options, cancelToken: cancelToken);
      
      final bool isResuming = response.statusCode == 206;
      int receivedBytes = 0;
      int actualTotalBytes = 0;

      if (isResuming) {
        debugPrint("[DownloadService] Server accepted Range header (206 Partial Content)");
        receivedBytes = existingBytes;
        final contentLength = int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;
        actualTotalBytes = contentLength + existingBytes;
      } else {
        debugPrint("[DownloadService] Server returned 200 OK (Full Content), starting fresh");
        receivedBytes = 0;
        actualTotalBytes = int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;
        if (existingBytes > 0) {
          // If we had a partial file but server gave us full content, truncate/overwrite
          await partFile.writeAsBytes([], mode: FileMode.write);
        }
      }

      debugPrint("[DownloadService] Total Bytes to download: $actualTotalBytes, Starting from: $receivedBytes");

      final sink = await partFile.open(mode: isResuming ? FileMode.append : FileMode.write);


      try {
        final stream = response.data.stream as Stream<List<int>>;
        DateTime lastUpdate = DateTime.now();

        await for (final chunk in stream) {
          await sink.writeFrom(chunk);
          receivedBytes += chunk.length;

          // Throttle UI updates to 10 FPS max to avoid lag
          final now = DateTime.now();
          if (now.difference(lastUpdate) > const Duration(milliseconds: 100) || receivedBytes == actualTotalBytes) {
            yield DownloadProgress(
              id: game.id,
              gameName: game.name,
              percent: actualTotalBytes > 0 ? receivedBytes / actualTotalBytes : 0,
              bytesReceived: receivedBytes,
              totalBytes: actualTotalBytes,
              status: 'Downloading...',
            );
            lastUpdate = now;
          }
        }
      } finally {
        await sink.close();
      }

      // Download complete, rename .part to final
      File file = await partFile.rename(finalPath);
      String currentPath = finalPath;

      // Extraction logic
      try {
        debugPrint("=== DOWNLOAD COMPLETION DEBUG ===");
        debugPrint("Game: ${game.name}, hasMultipleFiles: ${game.isMultiFile}");
        
        bool isZipSignature = false;
        if (await file.exists()) {
          final raf = await file.open();
          final bytes = await raf.read(4);
          await raf.close();

          isZipSignature = bytes.length == 4 &&
              bytes[0] == 0x50 &&
              bytes[1] == 0x4B &&
              bytes[2] == 0x03 &&
              bytes[3] == 0x04;

          if (isZipSignature && !currentPath.toLowerCase().endsWith('.zip')) {
            final newPath = '$currentPath.zip';
            await file.rename(newPath);
            currentPath = newPath;
          }
        }

        final isWindowsGame = ['windows', 'pc', 'win'].contains(game.platformSlug?.toLowerCase() ?? '');
        final isArchive = currentPath.toLowerCase().endsWith('.zip') ||
            currentPath.toLowerCase().endsWith('.7z');
        
        final platformSupportsArchive = directoryService.platformSupportsArchive(game.platformSlug);

        // We only want to extract if:
        // 1. It's a multi-file game (RomM says it has multiple files)
        // 2. It's a Windows game in an archive (usually needs extraction to run an EXE)
        // 3. It's a ZIP/archive but the platform emulator DOES NOT support archives natively
        final shouldExtract = game.isMultiFile || 
                             (isWindowsGame && isArchive) || 
                             ((isZipSignature || isArchive) && !platformSupportsArchive);
        
        if (shouldExtract) {
          yield DownloadProgress(
            id: game.id,
            gameName: game.name,
            percent: 1.0,
            status: 'Extracting...',
          );
          await _extractMultiFile(game, currentPath);
        }
        
        yield DownloadProgress(
          id: game.id,
          gameName: game.name,
          percent: 1.0,
          isComplete: true,
          status: 'Done!',
        );
      } catch (e) {
        yield DownloadProgress(
          id: game.id,
          gameName: game.name,
          error: 'Extraction failed: $e',
        );
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        debugPrint("[DownloadService] Download paused/canceled for: ${game.name}");
      } else {
        String errorMsg = 'Download failed: $e';
        if (e is DioException) {
          if (e.response?.statusCode == 416) {
            errorMsg = 'Range error. Retrying from start...';
            if (await partFile.exists()) await partFile.delete();
          } else if (e.response?.statusCode == 404) {
            errorMsg = 'File not found on server (404).';
          }
        }
        yield DownloadProgress(id: game.id, gameName: game.name, error: errorMsg);
      }
    }
  }

  /// Extracts a multi-file zip into a folder named after the game,
  /// then deletes the zip. Finds the main ROM by largest file size.
  Future<void> _extractMultiFile(Game game, String zipPath) async {
    final romDir = await directoryService.getRomDirectory(game);
    // Sanitize game name for use as folder name - matches DirectoryService sanitization
    final folderName = game.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    String extractDir = p.join(romDir, folderName);

    debugPrint('[DownloadService] Extraction starting...');
    debugPrint('[DownloadService] Zip Path: $zipPath');
    debugPrint('[DownloadService] Extract Dir: $extractDir');

    // If the extract directory path is already a file (e.g. game.name is "Game.zip" 
    // and we're extracting "Game.zip"), we must use an alternative folder name
    // to avoid "Not a directory" (Errno 20) error.
    if (extractDir == zipPath) {
      extractDir = p.join(romDir, '${folderName}_extracted');
      debugPrint('[DownloadService] Path conflict detected. Using: $extractDir');
    }

    await Directory(extractDir).create(recursive: true);

    try {
      await extractionService.extract(zipPath, extractDir);
      debugPrint('[DownloadService] Extraction complete. Deleting zip.');
      await File(zipPath).delete();
    } catch (e) {
      debugPrint('[DownloadService] Extraction Error: $e');
      if (e.toString().contains('Unsupported archive format')) {
        // File is not an archive - leave it as downloaded
        debugPrint('[DownloadService] Not an archive, keeping original file.');
        return;
      }
      rethrow;
    }
  }
}