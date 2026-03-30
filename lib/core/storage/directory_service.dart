import 'dart:io' as io;
import 'dart:io' show Directory, File, Process;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/romm/romm_models.dart';

class DirectoryService {
  static const String _romsRootPathKey = 'romsRootPath';
  static const String _emulatorsRootPathKey = 'emulatorsRootPath';

  // Known extensions per platform slug
  static const Map<String, List<String>> _platformExtensions = {
    'switch': ['.nsp', '.xci', '.nsz', '.xcz'],
    'nintendo-switch': ['.nsp', '.xci', '.nsz', '.xcz'],
    'ns': ['.nsp', '.xci', '.nsz', '.xcz'],
    'gba': ['.gba', '.zip'],
    'gbc': ['.gbc', '.gb', '.zip'],
    'gb': ['.gb', '.gbc', '.zip'],
    'nds': ['.nds', '.zip'],
    'n64': ['.z64', '.n64', '.v64', '.zip'],
    'snes': ['.sfc', '.smc', '.zip'],
    'nes': ['.nes', '.zip'],
    'psx': ['.bin', '.cue', '.iso', '.img', '.chd'],
    'ps2': ['.iso', '.bin', '.chd'],
    'ps3': ['.pkg', '.iso'],
    'psp': ['.iso', '.cso', '.pbp'],
    'gc': ['.iso', '.gcm', '.rvz', '.wbfs'],
    'gamecube': ['.iso', '.gcm', '.rvz', '.wbfs'],
    'wii': ['.iso', '.wbfs', '.rvz'],
    'dreamcast': ['.chd', '.gdi', '.cdi', '.iso'],
    'megadrive': ['.md', '.bin', '.gen', '.zip'],
    'genesis': ['.md', '.bin', '.gen', '.zip'],
  };

  late String romsRootPath;
  late String emulatorsRootPath;
  final Map<String, String> _emulatorPathOverrides = {};

  DirectoryService();

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final String defaultBase;
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux) {
      final appSupport = await getApplicationSupportDirectory();
      defaultBase = appSupport.path;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      defaultBase = docsDir.path;
    }

    romsRootPath = prefs.getString(_romsRootPathKey) ?? '$defaultBase/ROMs';
    emulatorsRootPath = prefs.getString(_emulatorsRootPathKey) ?? '$defaultBase/Emulators';
    await _ensureDirectoryExists(romsRootPath);
    await _ensureDirectoryExists(emulatorsRootPath);
    await loadEmulatorPathOverrides();
  }

  Future<void> loadEmulatorPathOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith('emu_path_')) {
        final emuId = key.replaceFirst('emu_path_', '');
        final path = prefs.getString(key);
        if (path != null) {
          _emulatorPathOverrides[emuId] = path;
        }
      }
    }
  }

  Future<void> setEmulatorPathOverride(String emulatorId, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emu_path_$emulatorId', path);
    _emulatorPathOverrides[emulatorId] = path;
  }

  String? getEmulatorPathOverride(String emulatorId) => _emulatorPathOverrides[emulatorId];

  Future<void> _ensureDirectoryExists(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  Future<void> setRomsRoot(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_romsRootPathKey, path);
    romsRootPath = path;
    await _ensureDirectoryExists(path);
  }

  Future<void> setEmulatorsRoot(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emulatorsRootPathKey, path);
    emulatorsRootPath = path;
    await _ensureDirectoryExists(path);
  }

  Future<String> getRomDirectory(Game game) async {
    final platformSlug = game.platformSlug ?? 'unknown';
    final dirPath = '$romsRootPath/$platformSlug';
    await _ensureDirectoryExists(dirPath);
    return dirPath;
  }

  Future<String> getRomFilePath(Game game) async {
    final romDir = await getRomDirectory(game);
    final fileName = game.fsName ?? game.fileName ?? game.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '$romDir/$fileName';
  }

  /// Tries to find the actual ROM file on disk.
  /// First checks the exact path, then tries common extensions for the platform.
  /// Returns the found path or null if not found.
  Future<String?> findExistingRomPath(Game game) async {
    final romDir = await getRomDirectory(game);
    final baseName = game.fsName ?? game.fileName ?? game.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final exactPath = '$romDir/$baseName';

    // Check exact path first (file or directory)
    if (await File(exactPath).exists()) return exactPath;
    if (await Directory(exactPath).exists()) return exactPath;

    // Check multi-file folder named after game name
    final folderName = game.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final multiFileDir = Directory('$romDir/$folderName');
    if (await multiFileDir.exists()) {
      // Windows games: return the folder itself so WindowsStrategy can find the exe
      final isWindowsGame = ['windows', 'pc', 'win'].contains(game.platformSlug?.toLowerCase() ?? '');
      if (isWindowsGame) return multiFileDir.path;

      // Other platforms: find largest file inside — that's the main ROM
      File? largestFile;
      int largestSize = 0;
      await for (final entity in multiFileDir.list(recursive: true)) {
        if (entity is File) {
          final size = await entity.length();
          if (size > largestSize) {
            largestSize = size;
            largestFile = entity;
          }
        }
      }
      if (largestFile != null) return largestFile.path;
    }

    // If baseName has no extension, try known extensions for this platform
    if (!baseName.contains('.')) {
      final extensions = _platformExtensions[game.platformSlug?.toLowerCase()] ?? [];
      for (final ext in extensions) {
        final candidate = '$romDir/$baseName$ext';
        if (await File(candidate).exists()) return candidate;
      }

      // Scan directory for any file starting with baseName
      final dir = Directory(romDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            final fname = entity.uri.pathSegments.last;
            if (fname.toLowerCase().startsWith(baseName.toLowerCase())) {
              return entity.path;
            }
          }
        }
      }
    }

    return null;
  }

  Future<String?> _getWindowsAppData() async {
    try {
      final result = await Process.run('cmd', ['/c', 'echo %APPDATA%'], runInShell: false);
      final path = result.stdout.toString().trim();
      if (path.isEmpty || path.contains('%APPDATA%')) return null;
      return path;
    } catch (e) {
      return null;
    }
  }

  Future<String?> resolveSevenZipPath() async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final appData = await _getWindowsAppData();
      if (appData == null) return null;

      final dest = File('$appData\\Freegosy\\thirdparty\\7zr.exe');
      if (await dest.exists()) return dest.path;

      try {
        await dest.parent.create(recursive: true);
        final byteData = await rootBundle.load('thirdparty/7zr.exe');
        await dest.writeAsBytes(byteData.buffer.asUint8List());
        return dest.path;
      } catch (e) {
        return null;
      }
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      final appSupport = await getApplicationSupportDirectory();
      final dest = File('${appSupport.path}/Freegosy/thirdparty/7zz');
      if (await dest.exists()) return dest.path;

      try {
        await dest.parent.create(recursive: true);
        final byteData = await rootBundle.load('thirdparty/7zz');
        await dest.writeAsBytes(byteData.buffer.asUint8List());
        await Process.run('chmod', ['+x', dest.path]);
        return dest.path;
      } catch (e) {
        return null;
      }
    } else if (defaultTargetPlatform == TargetPlatform.linux) {
      // Linux: Try to find system 7z
      try {
        final result = await Process.run('which', ['7z']);
        if (result.exitCode == 0) {
          return result.stdout.toString().trim();
        }
      } catch (e) {
        // ignore
      }
      return null;
    }

    return null;
  }

  Future<String> getEmulatorDirectory(String emulatorId) async {
    final override = getEmulatorPathOverride(emulatorId);
    if (override != null) return override;

    final dirPath = '$emulatorsRootPath/$emulatorId';
    await _ensureDirectoryExists(dirPath);
    return dirPath;
  }

  Future<String> getEmulatorSystemDirectory(String emulatorId) async {
    String dirPath;

    if (emulatorId == 'retroarch') {
      final emuDir = await getEmulatorDirectory(emulatorId);
      dirPath = '$emuDir/system';
    } else if (emulatorId == 'azahar') {
      if (io.Platform.isMacOS) {
        final home = io.Platform.environment['HOME'];
        if (home == null) throw Exception('HOME environment variable not set');
        dirPath = '$home/Library/Application Support/Azahar';
      } else if (io.Platform.isWindows) {
        final appData = await _getWindowsAppData();
        if (appData == null) throw Exception('APPDATA environment variable not set');
        dirPath = '$appData\\Azahar';
      } else {
        dirPath = await getEmulatorDirectory(emulatorId);
      }
    } else if (emulatorId == 'pcsx2') {
      if (io.Platform.isMacOS) {
        final home = io.Platform.environment['HOME'];
        if (home == null) throw Exception('HOME environment variable not set');
        dirPath = '$home/Library/Application Support/PCSX2';
      } else if (io.Platform.isWindows) {
        final appData = await _getWindowsAppData();
        if (appData == null) throw Exception('APPDATA environment variable not set');
        dirPath = '$appData\\PCSX2';
      } else {
        dirPath = await getEmulatorDirectory(emulatorId);
      }
    } else {
      dirPath = await getEmulatorDirectory(emulatorId);
    }

    await _ensureDirectoryExists(dirPath);
    return dirPath;
  }

  Future<String> getEmulatorExecutable(String emulatorId, String executableName) async {
    final emulatorDir = await getEmulatorDirectory(emulatorId);
    return '$emulatorDir/$executableName';
  }

  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async {
    final emulatorDir = await getEmulatorDirectory(emulatorId);
    final dir = Directory(emulatorDir);
    if (!await dir.exists()) {
      return null;
    }

    debugPrint("=== EMULATOR CHECK ===");
    debugPrint("Looking for: $executableName in $emulatorDir");
    await for (final e in dir.list()) {
      debugPrint("Found on disk: ${e.path}");
    }

    final direct = File('$emulatorDir/$executableName');
    if (await direct.exists()) {
      return direct.path;
    }

    if (executableName.contains('/')) {
      final parts = executableName.split('/');
      final firstPart = parts.first; // e.g. "PCSX2.app"
      final remaining = parts.sublist(1).join('/'); // e.g. "Contents/MacOS/PCSX2"

      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final dirName = entity.path.split(io.Platform.isWindows ? r'\' : '/').last;
          
          // Exact match or fuzzy match for versioned .app bundles (e.g. PCSX2-v2.6.3.app matches PCSX2.app)
          bool matches = dirName == firstPart;
          if (!matches && firstPart.endsWith('.app') && dirName.endsWith('.app')) {
            final stem = firstPart.substring(0, firstPart.length - 4).toLowerCase();
            if (dirName.toLowerCase().startsWith(stem)) {
              matches = true;
            }
          }

          if (matches) {
            final sub = File('${entity.path}/$remaining');
            if (await sub.exists()) {
              return sub.path;
            }
          }
        }
      }
      return null;
    }

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('/$executableName')) {
        return entity.path;
      }
      if (entity is Directory) {
        final sub = File('${entity.path}/$executableName');
        if (await sub.exists()) {
          return sub.path;
        }
      }
    }

    // Secondary check for core libraries if binary not found
    final ext = io.Platform.isMacOS ? '.dylib' : (io.Platform.isWindows ? '.dll' : '.so');
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final name = entity.path.split(io.Platform.isWindows ? r'\' : '/').last.toLowerCase();
        if (name.endsWith(ext) && name.contains(emulatorId.toLowerCase())) {
          debugPrint("Found core library fallback: ${entity.path}");
          return entity.path;
        }
      }
    }

    return null;
  }

  Future<bool> isEmulatorInstalled(String emulatorId, String executableName) async {
    final found = await findEmulatorExecutable(emulatorId, executableName);
    return found != null;
  }

  Future<bool> isRomDownloaded(Game game) async {
    final found = await findExistingRomPath(game);
    return found != null;
  }

  Future<void> deleteRom(Game game) async {
    final path = await findExistingRomPath(game);
    if (path != null) {
      if (await File(path).exists()) {
        await File(path).delete();
      } else if (await Directory(path).exists()) {
        await Directory(path).delete(recursive: true);
      }
    }
  }
}