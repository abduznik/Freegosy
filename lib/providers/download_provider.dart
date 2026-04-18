import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/downloader/download_service.dart';
import '../core/emulator/emulator_download_service.dart';
import '../core/extraction/extraction_service.dart';
import '../core/romm/romm_models.dart';
import '../core/constants/app_constants.dart';
import 'romm_provider.dart';

final downloadServiceProvider = FutureProvider<DownloadService?>((ref) async {
  final directoryService = await ref.watch(directoryServiceProvider.future);
  if (directoryService == null) return null;
  
  // Use a dedicated Dio instance for downloads with long timeouts
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(hours: 4), // Allow up to 4 hours for large ROMs
    headers: {
      'Accept-Encoding': 'identity', // Disable compression for large downloads to avoid proxy issues
      'User-Agent': 'Freegosy/${AppConstants.version}',
    },
  ));

  return DownloadService(
    dio: dio,
    directoryService: directoryService,
    extractionService: ExtractionService(directoryService),
  );
});

final emulatorDownloadServiceProvider =
    FutureProvider<EmulatorDownloadService?>((ref) async {
  final directoryService = await ref.watch(directoryServiceProvider.future);
  if (directoryService == null) return null;

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(minutes: 30),
    headers: {
      'Accept-Encoding': 'identity',
      'User-Agent': 'Freegosy/${AppConstants.version}',
    },
  ));

  return EmulatorDownloadService(
    dio,
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
      String emulatorId, String emulatorName, {String? architecture, String? buildType}) async {
    final service = await _ref.read(emulatorDownloadServiceProvider.future);
    if (service == null) return;
    service.downloadEmulator(emulatorId, architecture: architecture, buildType: buildType).listen((progress) {
      state = {...state, emulatorId: progress};
    });
  }

  void removeDownload(String gameId) {
    final newState = Map<String, DownloadProgress>.from(state);
    newState.remove(gameId);
    state = newState;
  }
}
