import 'dart:io' as io;
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../platform/platform_info.dart';
import 'app_path_resolver.dart';

/// [AppPathResolver] backed by plain `dart:io`, for use outside the Flutter
/// engine (e.g. the CLI). Replicates `path_provider`'s per-OS convention for
/// this app's identifiers exactly, so the CLI reads/writes the same
/// directory the Flutter app does:
///   - Windows: `%APPDATA%\abduznik\freegosy` (CompanyName\ProductName, from windows/runner/Runner.rc)
///   - macOS:   `~/Library/Application Support/com.abduznik.freegosy` (unsandboxed, from macos/Runner/Configs/AppInfo.xcconfig)
///   - Linux:   `$XDG_DATA_HOME/com.abduznik.freegosy` or `~/.local/share/com.abduznik.freegosy` (from linux/CMakeLists.txt APPLICATION_ID)
///
/// [loadAsset] always returns null — the CLI has no Flutter asset bundle.
/// Callers needing the bundled 7zip binary must have it already cached
/// (from a prior GUI-app run) or resolve it another way.
class CliAppPathResolver implements AppPathResolver {
  final PlatformInfo _platform;

  const CliAppPathResolver({PlatformInfo? platform}) : _platform = platform ?? const PlatformInfo('__default__');

  PlatformInfo get _resolvedPlatform => _platform.os == '__default__' ? PlatformInfo.current : _platform;

  @override
  Future<String> getApplicationSupportPath() async {
    final platform = _resolvedPlatform;
    if (platform.isWindows) {
      return p.join(platform.appData, 'abduznik', 'freegosy');
    } else if (platform.isMacOS) {
      return p.join(platform.homeDir, 'Library', 'Application Support', 'com.abduznik.freegosy');
    } else {
      final xdgDataHome = platform.environment['XDG_DATA_HOME'];
      final base = (xdgDataHome != null && xdgDataHome.isNotEmpty) ? xdgDataHome : p.join(platform.homeDir, '.local', 'share');
      return p.join(base, 'com.abduznik.freegosy');
    }
  }

  @override
  Future<String> getTemporaryPath() async => io.Directory.systemTemp.path;

  @override
  Future<Uint8List?> loadAsset(String assetPath) async => null;
}
