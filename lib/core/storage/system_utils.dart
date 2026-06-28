import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../platform/platform_info.dart';

class SystemUtils {
  static PlatformInfo _platform = PlatformInfo.current;

  static void configure({PlatformInfo? platform}) {
    _platform = platform ?? PlatformInfo.current;
  }

  /// Opens a file or directory in the system's file manager.
  static Future<void> openDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      debugPrint('[SystemUtils] Path does not exist: $path');
      return;
    }

    try {
      if (_platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (_platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (_platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (e) {
      debugPrint('[SystemUtils] Error opening directory: $e');
    }
  }

  /// Opens the application's data directory (application support).
  /// Uses [getApplicationSupportDirectory] on all platforms for consistency,
  /// which on Linux resolves to ~/.local/share/com.freegosy.app (XDG_DATA_HOME).
  static Future<void> openAppDataDirectory() async {
    final dir = await getApplicationSupportDirectory();
    await openDirectory(dir.path);
  }
}
