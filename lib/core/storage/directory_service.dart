import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/romm/romm_models.dart';

class DirectoryService {
  static const String _romsRootPathKey = 'romsRootPath';
  static const String _emulatorsRootPathKey = 'emulatorsRootPath';
  static const String _defaultRomsPath = 'Documents/Freegosy/ROMs';
  static const String _defaultEmulatorsPath = 'Documents/Freegosy/Emulators';

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

  DirectoryService();

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    romsRootPath = prefs.getString(_romsRootPathKey) ?? _defaultRomsPath;
    emulatorsRootPath = prefs.getString(_emulatorsRootPathKey) ?? _defaultEmulatorsPath;
    await _ensureDirectoryExists(romsRootPath);
    await _ensureDirectoryExists(emulatorsRootPath);
  }

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

    // If baseName has no extension, try known extensions for this platform
    if (!baseName.contains('.')) {
      final extensions = _platformExtensions[game.platformSlug?.toLowerCase()] ?? [];
      for (final ext in extensions) {
        final candidate = '$romDir/$baseName$ext';
        if (await File(candidate).exists()) {
          return candidate;
        }
      }

      // Also scan the directory for any file starting with baseName
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

  Future<String> getEmulatorDirectory(String emulatorId) async {
    final dirPath = '$emulatorsRootPath/$emulatorId';
    await _ensureDirectoryExists(dirPath);
    return dirPath;
  }

  Future<String> getEmulatorExecutable(String emulatorId, String executableName) async {
    final emulatorDir = await getEmulatorDirectory(emulatorId);
    return '$emulatorDir/$executableName';
  }

  Future<bool> isEmulatorInstalled(String emulatorId, String executableName) async {
    final dir = Directory(await getEmulatorDirectory(emulatorId));
    if (!await dir.exists()) return false;
    if (await File('${dir.path}/$executableName').exists()) return true;
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        if (await File('${entity.path}/$executableName').exists()) return true;
      }
    }
    return false;
  }

  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async {
    final dir = Directory(await getEmulatorDirectory(emulatorId));
    if (!await dir.exists()) return null;
    final direct = File('${dir.path}/$executableName');
    if (await direct.exists()) return direct.path;
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final sub = File('${entity.path}/$executableName');
        if (await sub.exists()) return sub.path;
      }
    }
    return null;
  }

  Future<bool> isRomDownloaded(Game game) async {
    final found = await findExistingRomPath(game);
    return found != null;
  }
}