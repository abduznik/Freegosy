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

  /// Whether this is the unpacking phase that follows the download.
  bool get isExtracting => status.startsWith('Extracting');

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
  /// Whether [path] ends in a real file extension. A dot inside a title
  /// ("Vol. 1 - Foo") makes `p.extension` return text with spaces, which is
  /// not an extension.
  @visibleForTesting
  static bool hasRealExtension(String path) {
    final ext = p.extension(path);
    return ext.length > 1 && ext.length <= 6 && !ext.contains(' ');
  }

  /// Whether [path] is an archive Freegosy unpacks after downloading (a Windows
  /// game, or a ROM for a platform whose emulator can't read archives).
  @visibleForTesting
  static bool isExtractableArchive(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.zip') || lower.endsWith('.7z') || lower.endsWith('.rar');
  }

  /// Name of the folder a multi-file game's files are unpacked into. The
  /// library lookup and delete find the game by this same name.
  static String multiFileFolderName(Game game) =>
      game.name.replaceAll(RegExp(r'[<>:"/\\|?]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  final Dio dio;
  final DirectoryService directoryService;
  final ExtractionService extractionService;

  DownloadService({
    required this.dio,
    required this.directoryService,
    required this.extractionService,
  });

  /// Parses a filename out of a `Content-Disposition` header value,
  /// preferring the RFC 5987 `filename*=UTF-8''...` form (percent-encoded)
  /// over the plain `filename="..."` form — RomM's plain form is itself
  /// sent percent-encoded (e.g. `filename="doom%202.vhd"`), so it is only
  /// used as a fallback when the extended form is absent.
  static String? parseContentDispositionFileName(String? header) {
    if (header == null || header.isEmpty) return null;

    final extendedMatch = RegExp(r"filename\*\s*=\s*UTF-8''([^;]+)", caseSensitive: false).firstMatch(header);
    if (extendedMatch != null) {
      final raw = extendedMatch.group(1)!.trim();
      try {
        return Uri.decodeComponent(raw);
      } catch (_) {
        return raw;
      }
    }

    final quotedMatch = RegExp(r'filename\s*=\s*"([^"]+)"', caseSensitive: false).firstMatch(header);
    if (quotedMatch != null) return quotedMatch.group(1);

    final bareMatch = RegExp(r'filename\s*=\s*([^;]+)', caseSensitive: false).firstMatch(header);
    if (bareMatch != null) return bareMatch.group(1)!.trim();

    return null;
  }

  /// [force] downloads even when the game is already on disk (adding files to
  /// a multi-file game). [singleFileName] names the file a partial download of
  /// a multi-file game is saved as when the server sends it bare, not zipped.
  Stream<DownloadProgress> download(Game game, String downloadUrl, {
    Map<String, String>? headers,
    CancelToken? cancelToken,
    bool force = false,
    String? singleFileName,
  }) async* {

    // `fsExtension` is empty/null for "single-file-foldered" games — RomM
    // stores these as a per-game folder containing one file, rather than a
    // flat "<name>.<ext>" at the platform root. `game.files` (the per-file
    // metadata array) is often empty here too: it's only populated when the
    // full game details were fetched (e.g. via getGame()), not on the
    // paginated list response the simple "Download" button normally acts
    // on — so this can't gate on `game.files.length == 1` alone, or the
    // fix silently never triggers for that common path (issue #44).
    final noFsExtension = game.fsExtension == null || game.fsExtension!.isEmpty;
    final singleFileMeta = game.files.length == 1 ? game.files[0]['file_name']?.toString() : null;
    // Fall back to the game's own top-level filename fields (always present,
    // unlike the files[] array) when per-file metadata isn't available.
    // `fs_name` is the game's FOLDER name for single-file-foldered games and
    // is not guaranteed to carry the real file extension, whereas `file_name`
    // does — so prefer it here (fsName is still the right choice everywhere
    // else that needs the folder name itself, e.g. getRomDirectory/getRomFilePath).
    final fallbackFileName = singleFileMeta ?? game.fileName ?? game.fsName;
    final bool isSingleFileFoldered = noFsExtension && fallbackFileName != null && fallbackFileName.isNotEmpty;

    String finalPath = await directoryService.getRomFilePath(game);
    if (isSingleFileFoldered) {
      finalPath = '$finalPath/$fallbackFileName';
    }

    // Ensure the final path has a file extension.
    // For single-file-foldered games where fsExtension was empty, the
    // path from getRomFilePath() may lack an extension (e.g. "Gamename"
    // instead of "Gamename.chd"). Pull the extension from the resolved
    // filename when the path has none.
    if (!hasRealExtension(finalPath) && isSingleFileFoldered) {
      final metaExt = p.extension(fallbackFileName).toLowerCase();
      if (metaExt.isNotEmpty) {
        finalPath = '$finalPath$metaExt';
      }
    }
    // A multi-file game arrives as one archive that is unpacked into its own
    // folder. The archive waits beside that folder, not in a folder named after
    // RomM's file name, which would be left behind empty.
    final isMultiFile = game.isMultiFile;
    final romDir = await directoryService.getRomDirectory(game);
    final multiFileFolder = multiFileFolderName(game);
    if (isMultiFile && multiFileFolder.isNotEmpty) {
      finalPath = p.join(romDir, '$multiFileFolder.download');
    }
    final partPath = '$finalPath.part';
    final partFile = File(partPath);

    int existingBytes = 0;
    if (await partFile.exists()) {
      existingBytes = await partFile.length();
    }

    // A leftover .part means this is a resume, never a finished game.
    if (!force && existingBytes == 0 && await directoryService.isRomDownloaded(game)) {
      yield DownloadProgress(id: game.id, gameName: game.name, percent: 1.0, isComplete: true);
      return;
    }
    await partFile.parent.create(recursive: true);



    debugPrint("[DownloadService] Starting download for: ${game.name}");
    
    yield DownloadProgress(
      id: game.id,
      gameName: game.name,
      percent: 0.0,
      bytesReceived: existingBytes,
      status: 'Downloading...',
    );
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

      // RomM's pre-fetched metadata (file_name/fs_name/files[]) doesn't always
      // carry the real extension for single-file-foldered games — sometimes
      // every one of those fields comes back extensionless. The download
      // response's Content-Disposition header is the authoritative source
      // (it reflects the actual file on disk), so use it to fix up the
      // extension when our best-effort guess above came up empty.
      final cdFileName = parseContentDispositionFileName(response.headers.value('content-disposition'));
      if (!isMultiFile && !hasRealExtension(finalPath)) {
        final cdExt = cdFileName != null ? p.extension(cdFileName) : '';
        if (cdExt.isNotEmpty) {
          debugPrint("[DownloadService] Correcting extension from Content-Disposition: $cdFileName");
          finalPath = '$finalPath$cdExt';
        }
      }

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
      // On Windows, if finalPath is a directory or locked, rename() throws Access Denied (errno 5).
      if (await Directory(finalPath).exists()) {
        debugPrint("[DownloadService] Destination is a directory. Removing to allow rename.");
        await Directory(finalPath).delete(recursive: true);
      } else if (await File(finalPath).exists()) {
        await File(finalPath).delete();
      }

      File file;
      try {
        file = await partFile.rename(finalPath);
      } catch (e) {
        debugPrint("[DownloadService] Rename failed ($e). Retrying with copy/delete fallback...");
        // Fallback for Windows "Access Denied" or "File Locked"
        // Wait a tiny bit for any scanner locks to release
        await Future.delayed(const Duration(milliseconds: 200));
        await partFile.copy(finalPath);
        await partFile.delete();
        file = File(finalPath);
      }
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

        // A partial download of a multi-file game can come back as the bare
        // file, not an archive: put it in the game's folder.
        if (isMultiFile && !isZipSignature && multiFileFolder.isNotEmpty) {
          final destDir = Directory(p.join(romDir, multiFileFolder));
          await destDir.create(recursive: true);
          final name = p.basename(cdFileName ?? singleFileName ?? game.fileName ?? multiFileFolder);
          final target = p.join(destDir.path, name);
          if (await File(target).exists()) await File(target).delete();
          try {
            await file.rename(target);
          } catch (_) {
            await file.copy(target);
            await file.delete();
          }
          yield DownloadProgress(id: game.id, gameName: game.name, percent: 1.0, isComplete: true, status: 'Done!');
          return;
        }

        final isWindowsGame = ['windows', 'pc', 'win'].contains(game.platformSlug?.toLowerCase() ?? '');
        final isArchive = isExtractableArchive(currentPath);
        
        final platformSupportsArchive = directoryService.platformSupportsArchive(game.platformSlug);

        // We only want to extract if:
        // 1. It's a multi-file game (RomM says it has multiple files)
        // 2. It's a Windows game in an archive (usually needs extraction to run an EXE)
        // 3. It's a ZIP/archive but the platform emulator DOES NOT support archives natively
        final shouldExtract = game.isMultiFile || 
                             (isWindowsGame && isArchive) || 
                             ((isZipSignature || isArchive) && !platformSupportsArchive);

        if (shouldExtract) {
          final extension = currentPath.split('.').last.toLowerCase();
          final extractStatus = 'Extracting ($extension)...';
          // Restart the bar for the unpacking phase; 0 shows as indeterminate
          // until the extractor reports a percentage.
          yield DownloadProgress(id: game.id, gameName: game.name, status: extractStatus);
          final fractions = StreamController<double>();
          final extraction = _extractMultiFile(game, currentPath, onProgress: fractions.add)
              .whenComplete(fractions.close);
          await for (final fraction in fractions.stream) {
            yield DownloadProgress(id: game.id, gameName: game.name, percent: fraction, status: extractStatus);
          }
          await extraction;
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
  Future<void> _extractMultiFile(Game game, String zipPath, {void Function(double fraction)? onProgress}) async {
    final romDir = await directoryService.getRomDirectory(game);
    // Sanitize game name for use as folder name - matches DirectoryService sanitization
    final folderName = multiFileFolderName(game);
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
      await extractionService.extract(zipPath, extractDir, onProgress: onProgress);
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