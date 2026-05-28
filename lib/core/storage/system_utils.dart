import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SystemUtils {
  /// Opens a file or directory in the system's file manager.
  static Future<void> openDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      debugPrint('[SystemUtils] Path does not exist: $path');
      return;
    }

    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
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
