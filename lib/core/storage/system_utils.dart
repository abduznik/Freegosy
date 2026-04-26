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

  /// Opens the application's configuration directory.
  static Future<void> openAppDataDirectory() async {
    String? path;
    if (Platform.isWindows) {
      path = Platform.environment['APPDATA'] ?? '';
      path = '$path\\Freegosy';
    } else if (Platform.isMacOS) {
      // Fix: Get app support directly
      final dir = await getApplicationSupportDirectory();
      path = dir.path; 
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      path = '$home/.config/Freegosy';
    }

    if (path != null && path.isNotEmpty) {
      await openDirectory(path);
    }
  }
}
