import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/romm/romm_models.dart'; // Assuming Game model is needed for getRomFilePath

class DirectoryService {
  static const String _romsRootPathKey = 'romsRootPath';
  static const String _emulatorsRootPathKey = 'emulatorsRootPath';
  static const String _defaultRomsPath = 'Documents/Freegosy/ROMs';
  static const String _defaultEmulatorsPath = 'Documents/Freegosy/Emulators';

  late String romsRootPath;
  late String emulatorsRootPath;

  DirectoryService(); // Constructor takes no args

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
    // Ensure platformSlug is not null or empty for directory creation
    final platformSlug = game.platformSlug ?? 'unknown';
    final dirPath = '$romsRootPath/$platformSlug';
    await _ensureDirectoryExists(dirPath);
    return dirPath;
  }

  Future<String> getRomFilePath(Game game) async {
    final romDir = await getRomDirectory(game);
    // Sanitize illegal characters for file names
    final fileName = game.name.replaceAll(RegExp(r'[<>:"/\|?*]'), '_');
    // Use game.fileName if available, otherwise sanitized game.name
    // For now, assuming game.fileName is not directly available or needed, using sanitized name
    return '$romDir/$fileName.rom'; // Assuming .rom extension, or derive from game data if possible
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
    final romPath = await getRomFilePath(game);
    return File(romPath).exists();
  }
}
