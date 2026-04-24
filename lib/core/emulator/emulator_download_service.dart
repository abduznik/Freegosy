import 'dart:async';
import 'dart:io';
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

  Stream<DownloadProgress> downloadEmulator(String emulatorId, {String? architecture, String? buildType}) async* {
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
    
    // Check for build-specific overrides (e.g., Nightly)
    if (buildType != null && buildType.isNotEmpty) {
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

        downloadUrl = await _releaseService.getLatestReleaseUrl(
          platform: ReleasePlatform.gitea,
          repo: repo,
          requiredFilters: required,
          excludedFilters: excluded,
          baseUrl: giteaBaseUrl,
        );
      } else {
        final String nightlyKey;
        if (Platform.isWindows) {
          nightlyKey = '${buildType}_windows_url'; // Fallback
        } else if (Platform.isMacOS) {
          nightlyKey = '${buildType}_macos_url';
        } else {
          nightlyKey = '${buildType}_linux_url';
        }
        
        final String specificNightlyKey;
        if (Platform.isWindows) {
          specificNightlyKey = 'windows_${buildType}_url';
        } else if (Platform.isMacOS) {
          specificNightlyKey = 'macos_${buildType}_url';
        } else {
          // Check for Steam Deck specific nightly if on Linux
          if (buildType == 'nightly' && _directoryService.isSteamDeck) {
            specificNightlyKey = 'linux_steamdeck_nightly_url';
          } else {
            specificNightlyKey = 'linux_${buildType}_url';
          }
        }

        downloadUrl = (definition[specificNightlyKey] ?? definition[nightlyKey]) as String?;
      }
    }

    // RPCS3 Special Case for macOS
    if (downloadUrl == null && emulatorId == 'rpcs3' && Platform.isMacOS) {
      final arch = architecture ?? 'x64';
      String repo;
      List<String> required;
      List<String> excluded = ['debug'];

      if (arch == 'x64') {
        repo = 'RPCS3/rpcs3-binaries-mac';
        required = ['macos', '.7z'];
      } else {
        // arm64
        repo = definition['github_repo_macos'] as String? ?? 'RPCS3/rpcs3-binaries-mac-arm64';
        required = List<String>.from(definition['github_asset_required_macos'] ?? ['macos', 'aarch64', '.7z']);
      }

      yield DownloadProgress(
        id: emulatorId,
        gameName: emulatorName,
        status: 'Fetching latest $arch release...',
      );

      downloadUrl = await _releaseService.getLatestReleaseUrl(
        platform: ReleasePlatform.github,
        repo: repo,
        requiredFilters: required,
        excludedFilters: excluded,
      );
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
      downloadUrl = await _releaseService.getLatestReleaseUrl(
        platform: ReleasePlatform.github,
        repo: repo,
        requiredFilters: required,
        excludedFilters: excluded,
      );
      if (downloadUrl == null) {
        yield DownloadProgress(
          id: emulatorId,
          gameName: emulatorName,
          error: 'No matching release asset found on GitHub',
        );
        return;
      }
    } else if (downloadUrl == null && type == 'gitea') {
      yield DownloadProgress(
        id: emulatorId,
        gameName: emulatorName,
        status: 'Fetching latest release...',
      );

      final repo = definition['gitea_repo'] as String;
      final giteaBaseUrl = definition['gitea_base_url'] as String?;

      // Determine platform-specific asset filters
      final String requiredKey;
      final String excludedKey;

      if (Platform.isWindows && definition.containsKey('gitea_asset_required_windows')) {
        requiredKey = 'gitea_asset_required_windows';
      } else if (Platform.isMacOS && definition.containsKey('gitea_asset_required_macos')) {
        requiredKey = 'gitea_asset_required_macos';
      } else if (Platform.isLinux && definition.containsKey('gitea_asset_required_linux')) {
        requiredKey = 'gitea_asset_required_linux';
      } else {
        requiredKey = 'gitea_asset_required';
      }

      if (Platform.isWindows && definition.containsKey('gitea_asset_excluded_windows')) {
        excludedKey = 'gitea_asset_excluded_windows';
      } else if (Platform.isMacOS && definition.containsKey('gitea_asset_excluded_macos')) {
        excludedKey = 'gitea_asset_excluded_macos';
      } else if (Platform.isLinux && definition.containsKey('gitea_asset_excluded_linux')) {
        excludedKey = 'gitea_asset_excluded_linux';
      } else {
        excludedKey = 'gitea_asset_excluded';
      }

      final required = List<String>.from(definition[requiredKey] ?? []);
      final excluded = List<String>.from(definition[excludedKey] ?? []);

      downloadUrl = await _releaseService.getLatestReleaseUrl(
        platform: ReleasePlatform.gitea,
        repo: repo,
        requiredFilters: required,
        excludedFilters: excluded,
        baseUrl: giteaBaseUrl,
      );

      if (downloadUrl == null) {
        yield DownloadProgress(
          id: emulatorId,
          gameName: emulatorName,
          error: 'No matching release asset found on Gitea',
        );
        return;
      }
    } else if (downloadUrl == null) {
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

          // Ensure binary is executable and remove quarantine on macOS/Linux
          final exeName = Platform.isWindows ? definition['windows_executable'] : (Platform.isMacOS ? definition['macos_executable'] : definition['linux_executable']);
          if (exeName != null) {
            final exePath = await _directoryService.findEmulatorExecutable(emulatorId, exeName as String);
            if (exePath != null) {
              if (Platform.isLinux || Platform.isMacOS) {
                await Process.run('chmod', ['+x', exePath]);
              }
              
              if (Platform.isMacOS) {
                // Remove quarantine attribute for the entire emulator directory
                // This prevents Gatekeeper from killing the process on direct launch
                await Process.run('xattr', ['-cr', emulatorDir]);

                // Special case for Ryujinx: Re-sign with hypervisor entitlement
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
        // We log to stderr but don't fail the download since the emulator might still work
        // or the user can fix it manually.
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
}
