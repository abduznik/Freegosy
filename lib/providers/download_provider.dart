import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/downloader/download_service.dart';
import '../core/emulator/emulator_download_service.dart';
import '../core/extraction/extraction_service.dart';
import '../core/romm/romm_models.dart';
import 'romm_provider.dart';

final downloadServiceProvider = FutureProvider<DownloadService?>((ref) async {
  final directoryService = await ref.watch(directoryServiceProvider.future);
  if (directoryService == null) return null;
  return DownloadService(
    dio: Dio(),
    directoryService: directoryService,
    extractionService: ExtractionService(directoryService),
  );
});

final emulatorDownloadServiceProvider =
    FutureProvider<EmulatorDownloadService?>((ref) async {
  final directoryService = await ref.watch(directoryServiceProvider.future);
  if (directoryService == null) return null;
  return EmulatorDownloadService(
    Dio(),
    directoryService,
    ExtractionService(directoryService),
  );
});

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, Map<String, DownloadProgress>>((ref) {
  return DownloadNotifier(ref);
});

class DownloadNotifier extends StateNotifier<Map<String, DownloadProgress>> {
  final Ref _ref;

  DownloadNotifier(this._ref) : super({});

  Future<void> startDownload(Game game, String downloadUrl,
      {Map<String, String>? headers}) async {
    final service = await _ref.read(downloadServiceProvider.future);
    if (service == null) return;
    service.download(game, downloadUrl, headers: headers).listen((progress) {
      state = {...state, game.id: progress};
    });
  }

  Future<void> startEmulatorDownload(
      String emulatorId, String emulatorName, {String? architecture}) async {
    final service = await _ref.read(emulatorDownloadServiceProvider.future);
    if (service == null) return;
    service.downloadEmulator(emulatorId, architecture: architecture).listen((progress) {
      state = {...state, emulatorId: progress};
    });
  }

  void removeDownload(String gameId) {
    final newState = Map<String, DownloadProgress>.from(state);
    newState.remove(gameId);
    state = newState;
  }
}
