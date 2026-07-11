import 'dart:io';
import 'package:path/path.dart' as p;

class WindowsGameService {
  /// Executable extensions that WindowsGameService can launch.
  static const launchableExtensions = ['.exe', '.bat', '.cmd'];

  /// Finds the main executable in [gameDir].
  /// First tries to match [hint] (game name), then falls back to largest .exe.
  /// Searches for .exe, .bat, and .cmd files.
  /// Skips macOS metadata (__MACOSX) and redistributable (_CommonRedist) folders.
  Future<String?> findExecutable(String gameDir, {String? hint}) async {
    final dir = Directory(gameDir);
    if (!await dir.exists()) return null;

    final exeFiles = <File>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final ext = entity.path.toLowerCase();
        if (launchableExtensions.any((e) => ext.endsWith(e))) {
          // Skip macOS resource forks (._filename)
          final basename = p.basename(entity.path);
          if (basename.startsWith('._')) continue;
          // Skip files inside __MACOSX or _CommonRedist folders
          final relPath = entity.path.substring(gameDir.length).toLowerCase();
          if (relPath.contains('__macosx') || relPath.contains('_commonredist')) continue;
          final name = basename.toLowerCase();
          if (_shouldSkipExe(name)) continue;
          exeFiles.add(entity);
        }
      }
    }

    if (exeFiles.isEmpty) return null;

    // Try hint match first (game name similarity)
    if (hint != null) {
      final hintTokens = _tokenize(hint);
      int bestScore = 0;
      File? bestMatch;

      for (final exe in exeFiles) {
        final exeTokens = _tokenize(p.basenameWithoutExtension(exe.path));
        int score = 0;
        for (final token in hintTokens) {
          if (exeTokens.any((t) => t.contains(token) || token.contains(t))) score++;
        }
        if (score > bestScore) {
          bestScore = score;
          bestMatch = exe;
        }
      }

      if (bestMatch != null && bestScore > 0) return bestMatch.path;
    }

    // Fall back to largest exe (preferring .exe over .bat/.cmd)
    final exes = exeFiles.where((f) => f.path.toLowerCase().endsWith('.exe')).toList();
    final candidates = exes.isNotEmpty ? exes : exeFiles;

    File? largest;
    int largestSize = 0;
    for (final exe in candidates) {
      final size = await exe.length();
      if (size > largestSize) {
        largestSize = size;
        largest = exe;
      }
    }

    return largest?.path;
  }

  /// Tokenizes a name for fuzzy matching.
  /// "Family Guy: Back to the Multiverse" → {"family", "guy", "back", "multiverse"}
  static Set<String> _tokenize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2)
        .toSet();
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

  /// Launches the executable at [exePath] with optional [arguments].
  /// For .bat/.cmd files, runs via cmd.exe to ensure proper execution.
  Future<void> launch(String exePath, {List<String> arguments = const []}) async {
    final dir = File(exePath).parent.path;
    final ext = p.extension(exePath).toLowerCase();

    if (ext == '.bat' || ext == '.cmd') {
      // Run batch files via cmd.exe
      await Process.start(
        'cmd.exe',
        ['/c', exePath, ...arguments],
        workingDirectory: dir,
        mode: ProcessStartMode.detached,
      );
    } else {
      await Process.start(
        exePath,
        arguments,
        workingDirectory: dir,
        mode: ProcessStartMode.detached,
      );
    }
  }
}