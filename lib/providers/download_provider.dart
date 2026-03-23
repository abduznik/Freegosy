import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import '../core/downloader/download_service.dart';
import '../core/romm/romm_models.dart';
import 'romm_provider.dart';

final downloadServiceProvider = FutureProvider<DownloadService?>((ref) async {
  final directoryService = await ref.watch(directoryServiceProvider.future);
  if (directoryService == null) return null;
  return DownloadService(dio: Dio(), directoryService: directoryService);
});

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, Map<String, DownloadProgress>>((ref) {
  final downloadService = ref.watch(downloadServiceProvider).asData?.value;
  if (downloadService == null) return DownloadNotifier(null);
  return DownloadNotifier(downloadService);
});

class DownloadNotifier extends StateNotifier<Map<String, DownloadProgress>> {
  final DownloadService? _service;

  DownloadNotifier(this._service) : super({});

  Future<void> startDownload(Game game, String downloadUrl, {Map<String, String>? headers}) async {
    if (_service == null) return;
    _service!.download(game, downloadUrl, headers: headers).listen((progress) {
      state = {...state, game.id: progress};
    });
  }

  void removeDownload(String gameId) {
    final newState = Map<String, DownloadProgress>.from(state);
    newState.remove(gameId);
    state = newState;
  }
}
