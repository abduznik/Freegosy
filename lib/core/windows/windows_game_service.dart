import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class WindowsGameService {
  /// Finds the main executable in [gameDir].
  /// First tries to match [hint] (game name), then falls back to largest .exe.
  Future<String?> findExecutable(String gameDir, {String? hint}) async {
    final dir = Directory(gameDir);
    if (!await dir.exists()) return null;

    final exeFiles = <File>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
        // Skip known non-game executables
        final name = p.basename(entity.path).toLowerCase();
        if (_shouldSkipExe(name)) continue;
        exeFiles.add(entity);
      }
    }

    if (exeFiles.isEmpty) return null;

    // Try hint match first (game name similarity)
    if (hint != null) {
      final hintLower = hint.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      for (final exe in exeFiles) {
        final exeName = p.basenameWithoutExtension(exe.path)
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (exeName.contains(hintLower) || hintLower.contains(exeName)) {
          return exe.path;
        }
      }
    }

    // Fall back to largest exe
    File? largest;
    int largestSize = 0;
    for (final exe in exeFiles) {
      final size = await exe.length();
      if (size > largestSize) {
        largestSize = size;
        largest = exe;
      }
    }

    return largest?.path;
  }

  bool _shouldSkipExe(String name) {
    const skipList = [
      'uninstall', 'uninst', 'setup', 'install', 'redist',
      'vc_redist', 'vcredist', 'directx', 'dxsetup',
      'dotnet', 'crashreport', 'crashhandler', 'bugsplat',
      'upc', 'easyanticheat', 'battleye', 'launcher_helper',
    ];
    return skipList.any((s) => name.contains(s));
  }

  /// Launches the exe at [exePath].
  Future<void> launch(String exePath) async {
    final dir = File(exePath).parent.path;
    await Process.start(
      exePath,
      [],
      workingDirectory: dir,
      mode: ProcessStartMode.detached,
    );
  }
}