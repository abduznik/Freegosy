import 'package:dio/dio.dart';
import 'dart:async';
import 'dart:io';
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

  DownloadProgress({
    required this.id,
    required this.gameName,
    this.percent = 0.0,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.isComplete = false,
    this.error,
  });
}

class DownloadService {
  final Dio dio;
  final DirectoryService directoryService;

  DownloadService({required this.dio, required this.directoryService});

  // Modified signature to accept downloadUrl
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
      ).then((_) {
        controller.add(DownloadProgress(
          id: game.id,
          gameName: game.name,
          percent: 1.0,
          isComplete: true,
        ));
        controller.close();
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
}
