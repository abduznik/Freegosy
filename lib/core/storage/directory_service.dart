import 'dart:io' as io;
import 'dart:io' show Directory, File, Process;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/rom_constants.dart';
import 'package:freegosy/core/storage/file_system_index.dart';
import 'package:freegosy/core/storage/rom_lookup_service.dart';
import 'package:freegosy/core/emulator/linux_strategies/linux_environment_strategy.dart';
import 'package:freegosy/core/emulator/linux_strategies/native_linux_strategy.dart';
import 'package:freegosy/core/emulator/linux_strategies/emudeck_strategy.dart';
import 'package:freegosy/core/emulator/linux_strategies/retrodeck_strategy.dart';

class DirectoryService {
  static const String _romsRootPathKey = 'romsRootPath';
  static const String _emulatorsRootPathKey = 'emulatorsRootPath';
  static const String _linuxSyncPresetKey = 'linuxSyncPreset';
  static const String _linuxPresetRootKey = 'emudeckRootPath';

  final SharedPreferences _prefs;
  late String romsRootPath;
  late String emulatorsRootPath;
  String linuxSyncPreset = 'default';
  String? linuxPresetRootPath;
  final Map<String, String> _emulatorPathOverrides = {};
  StorageStatus status = const StorageStatus();
  
  LinuxEnvironmentStrategy? _linuxStrategy;

  DirectoryService(this._prefs);

  bool get isSteamDeck {
    if (!io.Platform.isLinux) return false;
    final home = io.Platform.environment['HOME'] ?? '';
    return home == '/home/deck' || io.Directory('/home/deck').existsSync();
  }

  Future<String?> detectEmuDeckRoot() async {
    final home = io.Platform.environment['HOME'] ?? '/home/deck';
    final mediaDir = io.Directory('/run/media');
    if (await mediaDir.exists()) {
      try {
        final List<io.FileSystemEntity> users = await mediaDir.list().toList();
        for (final userDir in users) {
          if (userDir is! io.Directory) continue;
          final candidate1 = p.join(userDir.path, 'Emulation');
          if (await io.Directory(candidate1).exists()) return userDir.path;
          final List<io.FileSystemEntity> mounts = await userDir.list().toList();
          for (final mountDir in mounts) {
            if (mountDir is! io.Directory) continue;
            final candidate2 = p.join(mountDir.path, 'Emulation');
            if (await io.Directory(candidate2).exists()) return mountDir.path;
          }
        }
      } catch (_) {}
    }
    final internal = p.join(home, 'Emulation');
    if (await io.Directory(internal).exists()) return home;
    return null;
  }

  LinuxEnvironmentStrategy get activeLinuxEnvironment {
    if (_linuxStrategy != null) return _linuxStrategy!;
    switch (linuxSyncPreset) {
      case 'emudeck': _linuxStrategy = EmuDeckStrategy(); break;
      case 'retrodeck': _linuxStrategy = RetroDeckStrategy(); break;
      default: _linuxStrategy = NativeLinuxStrategy();
    }
    return _linuxStrategy!;
  }

  Future<StorageStatus> initialize() async {
    try {
      linuxSyncPreset = _prefs.getString(_linuxSyncPresetKey) ?? 'default';
      linuxPresetRootPath = _prefs.getString(_linuxPresetRootKey);
      
      if (defaultTargetPlatform == TargetPlatform.linux) {
        if ((linuxSyncPreset == 'auto' || linuxSyncPreset == 'default') && linuxPresetRootPath == null) {
          final detectedRoot = await detectEmuDeckRoot();
          if (detectedRoot != null) {
            linuxPresetRootPath = detectedRoot;
            linuxSyncPreset = 'emudeck';
            await _prefs.setString(_linuxSyncPresetKey, 'emudeck');
            await _prefs.setString(_linuxPresetRootKey, linuxPresetRootPath!);
          } else {
            final home = io.Platform.environment['HOME'] ?? '';
            final retrodeckConfig = p.join(home, '.var', 'app', 'net.retrodeck.retrodeck');
            if (await io.Directory(retrodeckConfig).exists()) {
              linuxSyncPreset = 'retrodeck';
              await _prefs.setString(_linuxSyncPresetKey, 'retrodeck');
            }
          }
        }
      }

      _linuxStrategy = null;
      final String defaultBase = await getDefaultBase();
      final home = io.Platform.environment['HOME'] ?? '';

      if (defaultTargetPlatform == TargetPlatform.linux) {
        final customRoms = _prefs.getString(_romsRootPathKey);
        final customEmus = _prefs.getString(_emulatorsRootPathKey);
        romsRootPath = activeLinuxEnvironment.getRomsRoot(home, customRoms, linuxPresetRootPath);
        emulatorsRootPath = activeLinuxEnvironment.getEmulatorsRoot(home, customEmus, linuxPresetRootPath);
      } else {
        romsRootPath = _prefs.getString(_romsRootPathKey) ?? p.join(defaultBase, 'ROMs');
        emulatorsRootPath = _prefs.getString(_emulatorsRootPathKey) ?? p.join(defaultBase, 'Emulators');
      }

      final romsStatus = await _ensureDirectoryExists(romsRootPath);
      if (romsStatus.hasError) return status = romsStatus;
      final emusStatus = await _ensureDirectoryExists(emulatorsRootPath);
      if (emusStatus.hasError) return status = emusStatus;

      loadEmulatorPathOverrides();
      return status = const StorageStatus();
    } catch (e) {
      return status = StorageStatus(error: StorageError.unknown, message: e.toString());
    }
  }

  Future<String> getDefaultBase() async {
    final appSupport = await getApplicationSupportDirectory();
    return appSupport.path;
  }

  Future<String?> resolveSevenZipPath() async {
    final tempDir = await getTemporaryDirectory();
    final String exeName = io.Platform.isWindows ? '7zr.exe' : '7zz';
    final exeFile = io.File(p.join(tempDir.path, exeName));

    if (!await exeFile.exists()) {
      try {
        final data = await rootBundle.load('thirdparty/$exeName');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await exeFile.writeAsBytes(bytes);
        if (!io.Platform.isWindows) {
          await Process.run('chmod', ['+x', exeFile.path]);
        }
      } catch (e) {
        debugPrint('[DirectoryService] Failed to resolve 7zip: $e');
        return null;
      }
    }
    return exeFile.path;
  }

  Future<void> resetRomsRoot() async {
    await _prefs.remove(_romsRootPathKey);
    await initialize();
  }

  Future<void> resetEmulatorsRoot() async {
    await _prefs.remove(_emulatorsRootPathKey);
    await initialize();
  }

  Future<void> setLinuxSyncPreset(String preset) async {
    await _prefs.setString(_linuxSyncPresetKey, preset);
    linuxSyncPreset = preset;
    await initialize();
  }

  Future<void> setLinuxPresetRoot(String path) async {
    await _prefs.setString(_linuxPresetRootKey, path);
    linuxPresetRootPath = path;
    await initialize();
  }

  void loadEmulatorPathOverrides() {
    for (final key in _prefs.getKeys()) {
      if (key.startsWith('emu_path_')) {
        final emuId = key.replaceFirst('emu_path_', '');
        final path = _prefs.getString(key);
        if (path != null) _emulatorPathOverrides[emuId] = path;
      }
    }
  }

  Future<void> setEmulatorPathOverride(String emulatorId, String path) async {
    await _prefs.setString('emu_path_$emulatorId', path);
    _emulatorPathOverrides[emulatorId] = path;
  }

  Future<String?> getEmulatorUrlOverride(String emulatorId) async => _prefs.getString('emulator_url_override_$emulatorId');

  Future<void> setEmulatorUrlOverride(String emulatorId, String? url) async {
    if (url == null) await _prefs.remove('emulator_url_override_$emulatorId');
    else await _prefs.setString('emulator_url_override_$emulatorId', url);
  }

  String? getEmulatorPathOverride(String emulatorId) => _emulatorPathOverrides[emulatorId];

  Future<StorageStatus> _ensureDirectoryExists(String path) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        try { await directory.create(recursive: true); } catch (e) {
          if (e is io.FileSystemException && (e.message.contains('Permission denied') || e.osError?.errorCode == 13)) {
            return StorageStatus(error: StorageError.permissionDenied, message: 'Permission denied', failedPath: path);
          }
          return StorageStatus(error: StorageError.pathNotFound, message: 'Path not found', failedPath: path);
        }
      }
      return const StorageStatus();
    } catch (e) {
      return StorageStatus(error: StorageError.unknown, message: e.toString(), failedPath: path);
    }
  }

  Future<void> setRomsRoot(String path) async {
    await _prefs.setString(_romsRootPathKey, path);
    romsRootPath = path;
    status = await _ensureDirectoryExists(path);
  }

  Future<void> setEmulatorsRoot(String path) async {
    await _prefs.setString(_emulatorsRootPathKey, path);
    emulatorsRootPath = path;
    status = await _ensureDirectoryExists(path);
  }

  bool platformSupportsArchive(String? platformSlug) {
    if (platformSlug == null) return false;
    final extensions = RomConstants.platformExtensions[platformSlug.toLowerCase()] ?? [];
    return extensions.any((ext) => ext.toLowerCase() == '.zip' || ext.toLowerCase() == '.7z');
  }

  Future<bool> isRomDownloaded(Game game) async {
    final path = await findExistingRomPath(game);
    return path != null;
  }

  Future<String> getRomsDirectory() async => romsRootPath;

  Future<String> getRomDirectory(Game game) async {
    final platformSlug = game.platformSlug ?? 'unknown';
    final dirPath = p.join(romsRootPath, platformSlug);
    await _ensureDirectoryExists(dirPath);
    return dirPath;
  }

  Future<String> getRomFilePath(Game game) async {
    final romDir = await getRomDirectory(game);
    final fileName = game.fsName ?? game.fileName ?? game.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return p.join(romDir, fileName);
  }

  Future<String?> findExistingRomPath(Game game, {FileSystemIndex? index}) async {
    final romDir = await getRomDirectory(game);
    return RomLookupService.findExistingRomPath(game, romDir, index: index);
  }

  Future<String> getEmulatorDirectory(String emulatorId) async {
    final override = getEmulatorPathOverride(emulatorId);
    if (override != null) return override;
    final dirPath = p.join(emulatorsRootPath, emulatorId);
    await _ensureDirectoryExists(dirPath);
    return dirPath;
  }

  Future<String> getEmulatorAppSupportDirectory(String emulatorName, {String? platformSlug}) async {
    if (io.Platform.isMacOS) {
      final appSupport = await getApplicationSupportDirectory();
      return p.join(appSupport.parent.parent.path, 'Application Support', emulatorName);
    } else if (io.Platform.isWindows) {
      final appData = io.Platform.environment['APPDATA'] ?? '';
      return p.join(appData, emulatorName);
    } else if (io.Platform.isLinux) {
      final home = io.Platform.environment['HOME'] ?? '';
      return activeLinuxEnvironment.getEmulatorAppSupportDirectory(home, emulatorName, linuxPresetRootPath, platformSlug: platformSlug);
    }
    throw UnsupportedError('Platform not supported');
  }

  Future<String> getEmulatorBiosDirectory(String emulatorId, {String? platformSlug}) async {
    if (io.Platform.isLinux) {
      final home = io.Platform.environment['HOME'] ?? '';
      return activeLinuxEnvironment.getBiosPath(home, linuxPresetRootPath);
    }
    
    final emuDir = await getEmulatorDirectory(emulatorId);
    
    // RetroArch on Windows specifically looks for bios in its 'system' directory, 
    // which is usually next to the executable, but often inside a subfolder like 'RetroArch-Win64'
    if (emulatorId == 'retroarch' && io.Platform.isWindows) {
      final exePath = await findEmulatorExecutable('retroarch', 'RetroArch.exe');
      if (exePath != null) {
        final systemDir = p.join(io.File(exePath).parent.path, 'system');
        await _ensureDirectoryExists(systemDir);
        return systemDir;
      }
    }
    
    final dirPath = p.join(emuDir, 'BIOS');
    await _ensureDirectoryExists(dirPath);
    return dirPath;
  }

  Future<String> getEmulatorSystemDirectory(String emulatorId, {String? platformSlug}) async => getEmulatorBiosDirectory(emulatorId, platformSlug: platformSlug);

  Future<void> deleteEmulator(String emulatorId) async {
    final dirPath = await getEmulatorDirectory(emulatorId);
    final directory = io.Directory(dirPath);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> deleteRom(Game game) async {
    final path = await findExistingRomPath(game);
    if (path != null) {
      final file = io.File(path);
      if (await file.exists()) await file.delete();
      final dir = io.Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async {
    final emulatorDir = await getEmulatorDirectory(emulatorId);
    final dir = Directory(emulatorDir);
    if (!await dir.exists()) return null;

    // 1. Try direct path
    final direct = File(p.join(emulatorDir, executableName));
    if (await direct.exists()) return direct.path;

    // 2. Try with .exe extension on Windows
    if (io.Platform.isWindows && !executableName.toLowerCase().endsWith('.exe')) {
      final withExe = File(p.join(emulatorDir, '$executableName.exe'));
      if (await withExe.exists()) return withExe.path;
    }

    // 3. Environment-specific logic (e.g., Linux Flatpaks)
    if (io.Platform.isLinux) {
      final envPath = await activeLinuxEnvironment.findExecutable(emulatorId, executableName, emulatorsRootPath, linuxPresetRootPath);
      if (envPath != null) return envPath;
    }

    // 4. Handle nested structures (e.g., zip contains a folder like 'RetroArch-Win64/')
    // Search up to 2 levels deep to find the executable
    try {
      final List<io.FileSystemEntity> entities = await dir.list(recursive: true).toList();
      for (final entity in entities) {
        if (entity is io.File) {
          final fileName = p.basename(entity.path);
          if (fileName.toLowerCase() == executableName.toLowerCase() || 
              (io.Platform.isWindows && fileName.toLowerCase() == '${executableName.toLowerCase()}.exe')) {
            // Check depth
            final relative = p.relative(entity.path, from: emulatorDir);
            final depth = relative.split(io.Platform.pathSeparator).length;
            if (depth <= 3) { // Root/Subfolder/Executable.exe or Root/Executable.exe
              return entity.path;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DirectoryService] Error during recursive search: $e');
    }

    // 5. Fallback for specifically nested paths in definitions
    if (executableName.contains('/')) {
      final parts = executableName.split('/');
      final firstPart = parts.first;
      try {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is Directory && p.basename(entity.path) == firstPart) {
            final fullPath = p.join(entity.path, parts.sublist(1).join('/'));
            if (await File(fullPath).exists()) return fullPath;
          }
        }
      } catch (_) {}
    }
    
    return null;
  }

  Future<void> launchGame(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
    if (io.Platform.isLinux) {
      await activeLinuxEnvironment.launch(game, romPath, emulatorId, exePath, args: args);
      return;
    }

    final exeDir = io.File(exePath).parent.path;
    if (io.Platform.isWindows) {
      await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.detached, workingDirectory: exeDir);
    } else if (io.Platform.isMacOS) {
      // For macOS, we might need 'open -a' or direct execution
      if (exePath.contains('.app')) {
        final appPath = exePath.substring(0, exePath.indexOf('.app') + 4);
        await io.Process.run('open', ['-a', appPath, romPath, '--args', ...args]);
      } else {
        await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.detached, workingDirectory: exeDir);
      }
    }
  }

  Future<io.Process?> launchGameWithHandle(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
    if (io.Platform.isLinux) {
      return await activeLinuxEnvironment.launchWithHandle(game, romPath, emulatorId, exePath, args: args);
    }

    final exeDir = io.File(exePath).parent.path;
    if (io.Platform.isWindows) {
      return await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.normal, workingDirectory: exeDir);
    } else if (io.Platform.isMacOS) {
      if (exePath.contains('.app')) {
        // We can't easily get a handle with 'open', so we try direct execution if possible
        return await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.normal, workingDirectory: exeDir);
      } else {
        return await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.normal, workingDirectory: exeDir);
      }
    }
    return null;
  }

  Future<void> launchStandalone(String emulatorId, String exePath, {List<String> args = const []}) async {
    if (io.Platform.isLinux) {
      await activeLinuxEnvironment.launchStandalone(emulatorId, exePath, args: args);
      return;
    }

    final exeDir = io.File(exePath).parent.path;
    if (io.Platform.isWindows) {
      await io.Process.start(exePath, args, mode: io.ProcessStartMode.detached, workingDirectory: exeDir);
    } else if (io.Platform.isMacOS) {
      if (exePath.contains('.app')) {
        final appPath = exePath.substring(0, exePath.indexOf('.app') + 4);
        await io.Process.run('open', ['-a', appPath, '--args', ...args]);
      } else {
        await io.Process.start(exePath, args, mode: io.ProcessStartMode.detached, workingDirectory: exeDir);
      }
    }
  }

  Future<bool> isEmulatorInstalled(String emulatorId, String executableName) async {
    final path = await findEmulatorExecutable(emulatorId, executableName);
    return path != null;
  }

  static bool isRomFile(String platformSlug, String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext.isEmpty) return false;
    final validExtensions = RomConstants.platformExtensions[platformSlug.toLowerCase()] ?? [];
    return validExtensions.any((v) => v.toLowerCase() == ext);
  }
}
