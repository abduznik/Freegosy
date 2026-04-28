import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/downloader/download_service.dart';
import '../core/emulator/emulator_download_service.dart';
import '../core/extraction/extraction_service.dart';
import '../core/romm/romm_models.dart';
import '../core/constants/app_constants.dart';
import 'romm_provider.dart';
import 'shared_prefs_provider.dart';

final downloadServiceProvider = FutureProvider<DownloadService?>((ref) async {
  final directoryService = await ref.watch(directoryServiceProvider.future);
  final rommService = ref.watch(rommServiceProvider);
  if (directoryService == null || rommService == null) return null;

  // Use a dedicated Dio instance for downloads with long timeouts
  final dio = Dio(BaseOptions(
    baseUrl: rommService.config.baseUrl,
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(hours: 4), // Allow up to 4 hours for large ROMs
    headers: {
      'User-Agent': 'Freegosy/${AppConstants.version}',
    },
  ));

  if (kDebugMode || io.Platform.isLinux || io.Platform.isMacOS) {
    dio.interceptors.add(LogInterceptor(
      requestHeader: true,
      requestBody: false,
      responseHeader: true,
      responseBody: false,
      logPrint: (obj) => debugPrint('[Download-Network] $obj'),
    ));
  }

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
      'User-Agent': 'Freegosy/${AppConstants.version}',
    },
  ));

  if (kDebugMode || io.Platform.isLinux || io.Platform.isMacOS) {
    dio.interceptors.add(LogInterceptor(
      requestHeader: true,
      requestBody: false,
      responseHeader: true,
      responseBody: false,
      logPrint: (obj) => debugPrint('[Emulator-Network] $obj'),
    ));
  }

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
  final Map<String, CancelToken> _cancelTokens = {};

  DownloadNotifier(this._ref) : super({}) {
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final jsonStr = prefs.getString('active_downloads');
      if (jsonStr == null) return;

      final List<dynamic> list = jsonDecode(jsonStr);
      final Map<String, DownloadProgress> loaded = {};
      for (final item in list) {
        final p = DownloadProgress(
          id: item['id'],
          gameName: item['gameName'],
          percent: (item['percent'] as num).toDouble(),
          bytesReceived: item['bytesReceived'] as int,
          totalBytes: item['totalBytes'] as int,
          game: item['game'] != null ? Game.fromJson(item['game']) : null,
          downloadUrl: item['downloadUrl'],
          isPaused: true,
          status: 'Paused',
        );
        loaded[p.id] = p;
      }
      state = {...state, ...loaded};
    } catch (e) {
      debugPrint('Error loading download state: $e');
    }
  }

  Future<void> _saveState() async {
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final downloadsJson = state.values
          .where((p) => !p.isComplete)
          .map((p) => {
                'id': p.id,
                'gameName': p.gameName,
                'percent': p.percent,
                'bytesReceived': p.bytesReceived,
                'totalBytes': p.totalBytes,
                'game': p.game?.toJson(),
                'downloadUrl': p.downloadUrl,
              })
          .toList();
      await prefs.setString('active_downloads', jsonEncode(downloadsJson));
    } catch (e) {
      debugPrint('Error saving download state: $e');
    }
  }

  void _updateProgress(String id, DownloadProgress progress) {
    final oldProgress = state[id];
    
    // PREVENT RACE CONDITION: If the download is already paused in our state,
    // don't let a "Downloading" update from the stream (that might have been
    // in flight during the pause action) overwrite it back to an active state.
    if (oldProgress != null && oldProgress.isPaused && progress.status == 'Downloading...') {
      return;
    }

    // Use a local variable to update state once
    final newState = Map<String, DownloadProgress>.from(state);
    newState[id] = progress;
    state = newState;

    if (oldProgress != null) {
      // Check if we crossed a 10% boundary
      final int oldPercentInt = (oldProgress.percent * 100).floor();
      final int newPercentInt = (progress.percent * 100).floor();
      
      if ((newPercentInt ~/ 10) > (oldPercentInt ~/ 10) || 
          progress.isComplete || 
          progress.isPaused || 
          progress.error != null) {
        _saveState();
      }
    } else {
      _saveState();
    }
  }

  Future<void> startDownload(Game game, String downloadUrl,
      {Map<String, String>? headers}) async {
    // If already downloading and not paused, do nothing
    if (state[game.id] != null && !state[game.id]!.isPaused && _cancelTokens.containsKey(game.id)) {
      return;
    }

    final service = await _ref.read(downloadServiceProvider.future);
    final rommService = _ref.read(rommServiceProvider);
    if (service == null) return;

    // Use current auth headers if none provided
    final effectiveHeaders = headers ?? (rommService != null ? {'Authorization': rommService.authHeader} : null);

    final cancelToken = CancelToken();
    _cancelTokens[game.id] = cancelToken;

    service.download(game, downloadUrl, headers: effectiveHeaders, cancelToken: cancelToken).listen(
      (progress) {
        _updateProgress(game.id, progress.copyWith(game: game, downloadUrl: downloadUrl));
      },
      onDone: () {
        _cancelTokens.remove(game.id);
      },
      onError: (e) {
        _cancelTokens.remove(game.id);
        if (state.containsKey(game.id)) {
          _updateProgress(game.id, state[game.id]!.copyWith(error: e.toString()));
        }
      },
    );
  }

  void pauseDownload(String id) {
    _cancelTokens[id]?.cancel();
    _cancelTokens.remove(id);
    if (state.containsKey(id)) {
      final pausedProgress = state[id]!.copyWith(isPaused: true, status: 'Paused');
      state = {...state, id: pausedProgress};
      _saveState(); // Persist the paused state
    }
  }

  void cancelDownload(String id) {
    _cancelTokens[id]?.cancel();
    _cancelTokens.remove(id);

    // Attempt to delete partial file BEFORE removing from state so we have the game object
    _deletePartialFile(id).then((_) {
      removeDownload(id);
    });
  }

  Future<void> _deletePartialFile(String id) async {
    try {
      final progress = state[id];
      if (progress == null || progress.game == null) return;

      final dirService = await _ref.read(directoryServiceProvider.future);
      if (dirService == null) return;

      final path = await dirService.getRomFilePath(progress.game!);
      
      // Wait a tiny bit for Dio/OS to release the file handle
      await Future.delayed(const Duration(milliseconds: 100));

      // Delete .part file first as it's the most likely to exist during active download
      final partFile = io.File('$path.part');

      if (await partFile.exists()) {
        debugPrint('[DownloadNotifier] Deleting partial file: ${partFile.path}');
        await partFile.delete();
      }
      
      // Also check final path just in case rename happened
      final file = io.File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[DownloadNotifier] Error deleting partial file: $e');
    }
  }

  Future<void> startEmulatorDownload(
      String emulatorId, String emulatorName, {String? architecture, String? buildType, String? urlOverride}) async {
    // If already downloading, do nothing
    if (_cancelTokens.containsKey(emulatorId)) return;

    final service = await _ref.read(emulatorDownloadServiceProvider.future);
    if (service == null) return;

    final cancelToken = CancelToken();
    _cancelTokens[emulatorId] = cancelToken;

    service.downloadEmulator(emulatorId, architecture: architecture, buildType: buildType, urlOverride: urlOverride, cancelToken: cancelToken).listen(
      (progress) {
        _updateProgress(emulatorId, progress);
      },
      onDone: () {
        _cancelTokens.remove(emulatorId);
      },
      onError: (e) {
        _cancelTokens.remove(emulatorId);
      },
    );
  }

  void removeDownload(String id) {
    _cancelTokens[id]?.cancel();
    _cancelTokens.remove(id);
    final newState = Map<String, DownloadProgress>.from(state);
    newState.remove(id);
    state = newState;
    _saveState();
  }
}
