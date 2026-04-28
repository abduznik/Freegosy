import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../downloader/download_service.dart';
import '../storage/directory_service.dart';
import '../extraction/extraction_service.dart';
import 'emulator_registry_data.dart';
import 'release_service.dart';

class EmulatorDownloadService {
  final Dio _dio;
  final DirectoryService _directoryService;
  final ExtractionService _extractionService;
  late final ReleaseService _releaseService;

  EmulatorDownloadService(this._dio, this._directoryService, this._extractionService) {
    _releaseService = ReleaseService(_dio);
  }

  Future<List<Map<String, String>>> getLatestAssetsForEmulator(String emulatorId) async {
    final definition = kEmulatorDefinitions.firstWhere((d) => d['id'] == emulatorId);
    final repo = definition['github_repo'] as String? ?? definition['gitea_repo'] as String? ?? '';
    final platform = definition['type'] == 'github' ? ReleasePlatform.github : (definition['type'] == 'dolphin' ? ReleasePlatform.dolphin : ReleasePlatform.gitea);
    
    // Simplification: Re-use filters from definition
    final requiredKey = Platform.isWindows ? 'github_asset_required_windows' : 'github_asset_required_linux';
    final excludedKey = 'github_asset_excluded';
    
    return await _releaseService.getLatestReleaseAssets(
      platform: platform,
      repo: repo,
      requiredFilters: List<String>.from(definition[requiredKey] ?? []),
      excludedFilters: List<String>.from(definition[excludedKey] ?? []),
    );
  }

  Future<String?> resolveCurrentDownloadUrl(String emulatorId) async {
    final stored = await _directoryService.getEmulatorUrlOverride(emulatorId);
    if (stored != null) return stored;

    final assets = await getLatestAssetsForEmulator(emulatorId);
    if (assets.isNotEmpty) {
      return assets.first['url'];
    }
    return null;
  }

  Future<void> _reSignRyujinx(String exePath) async {
    final appPath = exePath.split('/Contents/MacOS/').first;
    
    final entitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key><true/>
    <key>com.apple.security.cs.allow-jit</key><true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
    <key>com.apple.security.cs.debugger</key><true/>
    <key>com.apple.security.cs.disable-executable-page-protection</key><true/>
    <key>com.apple.security.cs.disable-library-validation</key><true/>
    <key>com.apple.security.get-task-allow</key><true/>
    <key>com.apple.security.hypervisor</key><true/>
</dict>
</plist>
''';

    final tempFile = File('${Directory.systemTemp.path}/ryujinx_entitlements_download.plist');
    await tempFile.writeAsString(entitlements);

    try {
      final signResult = await Process.run('codesign', [
        '--sign', '-',
        '--force',
        '--deep',
        '--entitlements', tempFile.path,
        appPath,
      ]);

      if (signResult.exitCode != 0) {
        stderr.writeln('[Ryujinx Sign] codesign failed (${signResult.exitCode}): ${signResult.stderr}');
      }
    } catch (e) {
      stderr.writeln('[Ryujinx Sign] Error: $e');
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Stream<DownloadProgress> downloadEmulator(String emulatorId, {String? architecture, String? buildType, String? urlOverride, CancelToken? cancelToken}) async* {
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

    String? downloadUrl = urlOverride;
    downloadUrl ??= await _directoryService.getEmulatorUrlOverride(emulatorId);

    // Check for build-specific overrides (e.g., Nightly)
    if (downloadUrl == null && buildType != null && buildType.isNotEmpty) {
      final buildTypeRepoKey = '${buildType}_repo';
      final buildTypeTypeKey = '${buildType}_type';
      final currentBuildType = (definition[buildTypeTypeKey] ?? 'direct') as String;

      if (currentBuildType == 'gitea') {
        final repo = definition[buildTypeRepoKey] as String;
        final giteaBaseUrl = definition['gitea_base_url'] as String?;
        List<String> required = [];
        List<String> excluded = List<String>.from(definition['${buildType}_asset_excluded'] ?? []);

        if (Platform.isWindows) {
          required = List<String>.from(definition['${buildType}_asset_required_windows'] ?? []);
        } else if (Platform.isMacOS) {
          required = List<String>.from(definition['${buildType}_asset_required_macos'] ?? []);
        } else {
          if (_directoryService.isSteamDeck) {
            required = List<String>.from(definition['${buildType}_asset_required_steamdeck'] ?? []);
          } else {
            required = List<String>.from(definition['${buildType}_asset_required_linux'] ?? []);
          }
        }

        yield DownloadProgress(
          id: emulatorId,
          gameName: emulatorName,
          status: 'Fetching latest $buildType release...',
        );

        final assets = await _releaseService.getLatestReleaseAssets(
          platform: ReleasePlatform.gitea,
          repo: repo,
          requiredFilters: required,
          excludedFilters: excluded,
          baseUrl: giteaBaseUrl,
        );

        if (assets.isEmpty) {
          yield DownloadProgress(id: emulatorId, gameName: emulatorName, error: 'No matching release asset found on Gitea');
          return;
        } else if (assets.length > 1) {
          yield DownloadProgress(id: emulatorId, gameName: emulatorName, status: 'selection_required');
          return;
        }
        downloadUrl = assets.first['url'];
      }
    }

    if (downloadUrl == null && type == 'github') {
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

      String requiredKey = 'github_asset_required';
      String excludedKey = 'github_asset_excluded';
      if (Platform.isWindows) {
        if (definition.containsKey('github_asset_required_windows')) requiredKey = 'github_asset_required_windows';
        if (definition.containsKey('github_asset_excluded_windows')) excludedKey = 'github_asset_excluded_windows';
      } else if (Platform.isMacOS) {
        if (definition.containsKey('github_asset_required_macos')) requiredKey = 'github_asset_required_macos';
        if (definition.containsKey('github_asset_excluded_macos')) excludedKey = 'github_asset_excluded_macos';
      } else if (Platform.isLinux) {
        if (definition.containsKey('github_asset_required_linux')) requiredKey = 'github_asset_required_linux';
        if (definition.containsKey('github_asset_excluded_linux')) excludedKey = 'github_asset_excluded_linux';
      }

      final required = List<String>.from(definition[requiredKey] ?? []);
      final excluded = List<String>.from(definition[excludedKey] ?? []);
      final assets = await _releaseService.getLatestReleaseAssets(
        platform: ReleasePlatform.github,
        repo: repo,
        requiredFilters: required,
        excludedFilters: excluded,
      );

      if (assets.isEmpty) {
        yield DownloadProgress(id: emulatorId, gameName: emulatorName, error: 'No matching release asset found on GitHub');
        return;
      } else if (assets.length > 1) {
        yield DownloadProgress(id: emulatorId, gameName: emulatorName, status: 'selection_required');
        return;
      }
      downloadUrl = assets.first['url'];
    } else if (downloadUrl == null && type == 'dolphin') {
      yield DownloadProgress(
        id: emulatorId,
        gameName: emulatorName,
        status: 'Fetching latest release from Dolphin site...',
      );

      final requiredKey = Platform.isWindows ? 'asset_required_windows' : (Platform.isMacOS ? 'asset_required_macos' : 'asset_required_linux');
      final required = List<String>.from(definition[requiredKey] ?? []);

      final assets = await _releaseService.getLatestReleaseAssets(
        platform: ReleasePlatform.dolphin,
        repo: '',
        requiredFilters: required,
      );

      if (assets.isEmpty) {
        yield DownloadProgress(id: emulatorId, gameName: emulatorName, error: 'No matching release asset found on Dolphin site');
        return;
      }
      downloadUrl = assets.first['url'];
    } else if (downloadUrl == null && type == 'gitea') {
      yield DownloadProgress(
        id: emulatorId,
        gameName: emulatorName,
        status: 'Fetching latest release...',
      );

      final repo = definition['gitea_repo'] as String;
      final baseUrl = definition['gitea_host'] != null ? 'https://${definition['gitea_host']}' : null;

      String requiredKey = 'gitea_asset_required';
      String excludedKey = 'gitea_asset_excluded';
      if (Platform.isWindows) {
        if (definition.containsKey('gitea_asset_required_windows')) requiredKey = 'gitea_asset_required_windows';
        if (definition.containsKey('gitea_asset_excluded_windows')) excludedKey = 'gitea_asset_excluded_windows';
      } else if (Platform.isMacOS) {
        if (definition.containsKey('gitea_asset_required_macos')) requiredKey = 'gitea_asset_required_macos';
        if (definition.containsKey('gitea_asset_excluded_macos')) excludedKey = 'gitea_asset_excluded_macos';
      } else if (Platform.isLinux) {
        if (definition.containsKey('gitea_asset_required_linux')) requiredKey = 'gitea_asset_required_linux';
        if (definition.containsKey('gitea_asset_excluded_linux')) excludedKey = 'gitea_asset_excluded_linux';
      }

      final required = List<String>.from(definition[requiredKey] ?? []);
      final excluded = List<String>.from(definition[excludedKey] ?? []);
      final assets = await _releaseService.getLatestReleaseAssets(
        platform: ReleasePlatform.gitea,
        repo: repo,
        requiredFilters: required,
        excludedFilters: excluded,
        baseUrl: baseUrl,
      );

      if (assets.isEmpty) {
        yield DownloadProgress(id: emulatorId, gameName: emulatorName, error: 'No matching release asset found on Gitea');
        return;
      } else if (assets.length > 1) {
        yield DownloadProgress(id: emulatorId, gameName: emulatorName, status: 'selection_required');
        return;
      }
      downloadUrl = assets.first['url'];
    } else if (downloadUrl == null && type == 'direct') {
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

    // Initial status update before starting the download
    controller.add(DownloadProgress(
      id: emulatorId,
      gameName: emulatorName,
      status: 'Downloading...',
      percent: 0.0,
    ));

    try {
      final options = Options(responseType: ResponseType.stream);
      final response = await _dio.get(downloadUrl, options: options, cancelToken: cancelToken);
      
      final totalBytes = int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;
      final file = File(tempFilePath);
      final sink = await file.open(mode: FileMode.write);
      int receivedBytes = 0;

      try {
        final stream = response.data.stream as Stream<List<int>>;
        await for (final chunk in stream) {
          await sink.writeFrom(chunk);
          receivedBytes += chunk.length;
          controller.add(DownloadProgress(
            id: emulatorId,
            gameName: emulatorName,
            percent: totalBytes > 0 ? receivedBytes / totalBytes : 0,
            bytesReceived: receivedBytes,
            totalBytes: totalBytes,
            status: 'Downloading...',
          ));
        }
      } finally {
        await sink.close();
      }

      try {
        final extension = downloadUrl.split('.').last.toLowerCase();
        controller.add(DownloadProgress(
          id: emulatorId,
          gameName: emulatorName,
          percent: 1.0,
          status: 'Extracting ($extension)...',
        ));
        await _extractionService.extract(tempFilePath, emulatorDir);

        final exeName = Platform.isWindows ? definition['windows_executable'] : (Platform.isMacOS ? definition['macos_executable'] : definition['linux_executable']);
        if (exeName != null) {
          final exePath = await _directoryService.findEmulatorExecutable(emulatorId, exeName as String);
          if (exePath != null) {
            if (Platform.isLinux || Platform.isMacOS) {
              await Process.run('chmod', ['+x', exePath]);
            }
            
            if (Platform.isMacOS) {
              await Process.run('xattr', ['-cr', emulatorDir]);
              if (emulatorId == 'ryujinx') {
                await _reSignRyujinx(exePath);
              }
            }
          }
        }

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
        final f = File(tempFilePath);
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        debugPrint("[EmulatorDownloadService] Download canceled: $emulatorId");
      } else {
        controller.add(DownloadProgress(
          id: emulatorId,
          gameName: emulatorName,
          error: 'Download failed: $e',
        ));
      }
    } finally {
      controller.close();
    }

    yield* controller.stream;
  }
}
