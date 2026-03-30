import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../downloader/download_service.dart';
import '../storage/directory_service.dart';
import '../extraction/extraction_service.dart';
import 'emulator_registry_data.dart';
import 'github_release_service.dart';

class EmulatorDownloadService {
  final Dio _dio;
  final DirectoryService _directoryService;
  final ExtractionService _extractionService;
  late final GithubReleaseService _githubService;

  EmulatorDownloadService(this._dio, this._directoryService, this._extractionService) {
    _githubService = GithubReleaseService(_dio);
  }

  Stream<DownloadProgress> downloadEmulator(String emulatorId) async* {
    final definition = kEmulatorDefinitions.firstWhere(
      (d) => d['id'] == emulatorId,
      orElse: () => {},
    );

    if (definition.isEmpty) {
      yield DownloadProgress(
        id: emulatorId,
        gameName: emulatorId,
        error: 'Emulator definition not found',
      );
      return;
    }

    final String emulatorName = definition['name'] as String? ?? emulatorId;
    final String type = definition['type'] as String? ?? 'direct';

    // Resolve download URL based on type
    String? downloadUrl;
    if (type == 'github') {
      yield DownloadProgress(
        id: emulatorId,
        gameName: emulatorName,
        status: 'Fetching latest release...',
      );
      
      String repo = definition['github_repo'] as String;
      if (Platform.isWindows && definition.containsKey('github_repo_windows')) {
        repo = definition['github_repo_windows'] as String;
      } else if (Platform.isMacOS && definition.containsKey('github_repo_macos')) {
        repo = definition['github_repo_macos'] as String;
      } else if (Platform.isLinux && definition.containsKey('github_repo_linux')) {
        repo = definition['github_repo_linux'] as String;
      }

      // Determine platform-specific asset filters with generic fallbacks
      final String requiredKey;
      final String excludedKey;

      if (Platform.isWindows && definition.containsKey('github_asset_required_windows')) {
        requiredKey = 'github_asset_required_windows';
      } else if (Platform.isMacOS && definition.containsKey('github_asset_required_macos')) {
        requiredKey = 'github_asset_required_macos';
      } else if (Platform.isLinux && definition.containsKey('github_asset_required_linux')) {
        requiredKey = 'github_asset_required_linux';
      } else {
        requiredKey = 'github_asset_required';
      }

      if (Platform.isWindows && definition.containsKey('github_asset_excluded_windows')) {
        excludedKey = 'github_asset_excluded_windows';
      } else if (Platform.isMacOS && definition.containsKey('github_asset_excluded_macos')) {
        excludedKey = 'github_asset_excluded_macos';
      } else if (Platform.isLinux && definition.containsKey('github_asset_excluded_linux')) {
        excludedKey = 'github_asset_excluded_linux';
      } else {
        excludedKey = 'github_asset_excluded';
      }

      final required = List<String>.from(definition[requiredKey] ?? []);
      final excluded = List<String>.from(definition[excludedKey] ?? []);
      downloadUrl = await _githubService.getLatestReleaseUrl(
        repo: repo,
        required: required,
        excluded: excluded,
      );
      if (downloadUrl == null) {
        yield DownloadProgress(
          id: emulatorId,
          gameName: emulatorName,
          error: 'No matching release asset found on GitHub',
        );
        return;
      }
    } else {
      if (Platform.isWindows) {
        downloadUrl = definition['windows_url'] as String?;
      } else if (Platform.isMacOS) {
        downloadUrl = definition['macos_url'] as String?;
      } else {
        downloadUrl = definition['linux_url'] as String?;
      }
    }

    if (downloadUrl == null) {
      yield DownloadProgress(
        id: emulatorId,
        gameName: emulatorName,
        error: 'This emulator is not available for your platform',
      );
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
              gameName: emulatorName,
              percent: received / total,
              bytesReceived: received,
              totalBytes: total,
              status: 'Downloading...',
            ));
          }
        },
        deleteOnError: true,
      ).then((_) async {
        try {
          controller.add(DownloadProgress(
            id: emulatorId,
            gameName: emulatorName,
            percent: 1.0,
            status: 'Extracting...',
          ));
          await _extractionService.extract(tempFilePath, emulatorDir);
          controller.add(DownloadProgress(
            id: emulatorId,
            gameName: emulatorName,
            percent: 1.0,
            isComplete: true,
            status: 'Done!',
          ));
        } catch (e) {
          controller.add(DownloadProgress(
            id: emulatorId,
            gameName: emulatorName,
            error: 'Extraction failed: $e',
          ));
        } finally {
          controller.close();
          final f = File(tempFilePath);
          if (await f.exists()) await f.delete();
        }
      }).catchError((e) {
        controller.add(DownloadProgress(
          id: emulatorId,
          gameName: emulatorName,
          error: 'Download failed: $e',
        ));
        controller.close();
      });

      yield* controller.stream;
    } catch (e) {
      yield DownloadProgress(
        id: emulatorId,
        gameName: emulatorName,
        error: 'Error: $e',
      );
    }
  }
}