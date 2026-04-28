import 'dart:io' as io;
import 'dart:io' show Directory, File, Process, FileSystemEntity;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/emulator/linux_strategies/linux_environment_strategy.dart';
import 'package:freegosy/core/emulator/linux_strategies/native_linux_strategy.dart';
import 'package:freegosy/core/emulator/linux_strategies/emudeck_strategy.dart';
import 'package:freegosy/core/emulator/linux_strategies/retrodeck_strategy.dart';

enum StorageError { none, pathNotFound, permissionDenied, unknown }

class StorageStatus {
  final StorageError error;
  final String? message;
  final String? failedPath;

  const StorageStatus({this.error = StorageError.none, this.message, this.failedPath});

  bool get hasError => error != StorageError.none;
}

class FileSystemIndex {
  final String rootPath;
  final Map<String, String> files; // lowercase name -> absolute path
  final Map<String, String> dirs;  // lowercase name -> absolute path
  final Map<String, int> fileSizes; // absolute path -> size

  FileSystemIndex({
    required this.rootPath,
    required this.files,
    required this.dirs,
    required this.fileSizes,
  });

  static Future<FileSystemIndex> build(String path) async {
    final Map<String, String> files = {};
    final Map<String, String> dirs = {};
    final Map<String, int> fileSizes = {};

    final rootDir = io.Directory(path);
    if (await rootDir.exists()) {
      try {
        await for (final entity in rootDir.list(recursive: false)) {
          final name = p.basename(entity.path).toLowerCase();
          if (entity is io.File) {
            files[name] = p.absolute(entity.path);
            try {
              fileSizes[p.absolute(entity.path)] = await entity.length();
            } catch (_) {}
          } else if (entity is io.Directory) {
            dirs[name] = p.absolute(entity.path);
          }
        }
      } catch (_) {}
    }

    return FileSystemIndex(
      rootPath: path,
      files: files,
      dirs: dirs,
      fileSizes: fileSizes,
    );
  }
}

class DirectoryService {
  static const String _romsRootPathKey = 'romsRootPath';
  static const String _emulatorsRootPathKey = 'emulatorsRootPath';
  static const String _linuxSyncPresetKey = 'linuxSyncPreset';
  static const String _emudeckRootPathKey = 'emudeckRootPath';

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
    'ps3': ['.pkg', '.iso', '.bin', '.edat'],
    'psp': ['.iso', '.cso', '.pbp'],
    'gc': ['.iso', '.gcm', '.rvz', '.wbfs'],
    'gamecube': ['.iso', '.gcm', '.rvz', '.wbfs'],
    'wii': ['.iso', '.wbfs', '.rvz'],
    'dreamcast': ['.chd', '.gdi', '.cdi', '.iso'],
    'megadrive': ['.md', '.bin', '.gen', '.zip'],
    'genesis': ['.md', '.bin', '.gen', '.zip'],
  };

  final SharedPreferences _prefs;
  late String romsRootPath;
  late String emulatorsRootPath;
  String linuxSyncPreset = 'default';
  String? emudeckRootPath;
  final Map<String, String> _emulatorPathOverrides = {};
  StorageStatus status = const StorageStatus();
  
  LinuxEnvironmentStrategy? _linuxStrategy;

  DirectoryService(this._prefs);

  bool get isSteamDeck {
    if (!io.Platform.isLinux) return false;
    final home = io.Platform.environment['HOME'] ?? '';
    return home == '/home/deck' || io.Directory('/home/deck').existsSync();
  }

  /// Detects EmuDeck root by scanning common mount points and internal home.
  Future<String?> detectEmuDeckRoot() async {
    final home = io.Platform.environment['HOME'] ?? '/home/deck';
    
    // 1. Check External SD / Removable Media FIRST (Most Steam Deck users prefer SD)
    final mediaDir = io.Directory('/run/media');
    if (await mediaDir.exists()) {
      try {
        final List<io.FileSystemEntity> users = await mediaDir.list().toList();
        for (final userDir in users) {
          if (userDir is! io.Directory) continue;

          // Check 1 level deep: /run/media/deck/Emulation
          final candidate1 = p.join(userDir.path, 'Emulation');
          if (await io.Directory(candidate1).exists()) return userDir.path;

          // Check 2 levels deep: /run/media/deck/LABEL/Emulation
          final List<io.FileSystemEntity> mounts = await userDir.list().toList();
          for (final mountDir in mounts) {
            if (mountDir is! io.Directory) continue;
            final candidate2 = p.join(mountDir.path, 'Emulation');
            if (await io.Directory(candidate2).exists()) {
              return mountDir.path;
            }
          }
        }
      } catch (_) {}
    }

    // 2. Check Internal Home LAST
    final internal = p.join(home, 'Emulation');
    if (await io.Directory(internal).exists()) return home;

    return null;
  }

  LinuxEnvironmentStrategy get activeLinuxEnvironment {
    if (_linuxStrategy != null) return _linuxStrategy!;
    
    switch (linuxSyncPreset) {
      case 'emudeck':
        _linuxStrategy = EmuDeckStrategy();
        break;
      case 'retrodeck':
        _linuxStrategy = RetroDeckStrategy();
        break;
      case 'auto':
        // For auto, we prefer EmuDeck if detected, then RetroDeck, then Native
        _linuxStrategy = EmuDeckStrategy(); // Defaulting to EmuDeck for now, logic refined in initialize
        break;
      default:
        _linuxStrategy = NativeLinuxStrategy();
    }
    return _linuxStrategy!;
  }

  Future<StorageStatus> initialize() async {
    try {
      linuxSyncPreset = _prefs.getString(_linuxSyncPresetKey) ?? 'default';
      emudeckRootPath = _prefs.getString(_emudeckRootPathKey);
      
      // Auto-detection logic for Linux
      if (defaultTargetPlatform == TargetPlatform.linux) {
        if (linuxSyncPreset == 'auto' || linuxSyncPreset == 'default') {
          // If we are in 'auto' or 'default', try to see if EmuDeck or RetroDeck is there.
          // BUT: If the user has already explicitly chosen a root, don't overwrite it with auto-detection.
          if (emudeckRootPath == null) {
            final detectedRoot = await detectEmuDeckRoot();
            if (detectedRoot != null) {
              emudeckRootPath = detectedRoot;
              linuxSyncPreset = 'emudeck';
              _linuxStrategy = EmuDeckStrategy();
              await _prefs.setString(_linuxSyncPresetKey, 'emudeck');
              await _prefs.setString(_emudeckRootPathKey, emudeckRootPath!);
            }
          } else if (linuxSyncPreset == 'default') {
             // If they are on 'default' (manual) but have an emudeckRootPath, 
             // we stay on 'default' unless it's the very first run.
          }
          
          if (linuxSyncPreset == 'default' || linuxSyncPreset == 'auto') {
            // Check for RetroDeck
            final home = io.Platform.environment['HOME'] ?? '';
            final retrodeckConfig = p.join(home, '.var', 'app', 'net.retrodeck.retrodeck');
            if (await io.Directory(retrodeckConfig).exists()) {
              linuxSyncPreset = 'retrodeck';
              _linuxStrategy = RetroDeckStrategy();
              await _prefs.setString(_linuxSyncPresetKey, 'retrodeck');
            }
          }
        }
      }

      // Reset strategy to force re-instantiation with correct preset
      _linuxStrategy = null;

      final String defaultBase = await getDefaultBase();
      final home = io.Platform.environment['HOME'] ?? '';

      if (defaultTargetPlatform == TargetPlatform.linux) {
        final customRoms = _prefs.getString(_romsRootPathKey);
        final customEmus = _prefs.getString(_emulatorsRootPathKey);
        
        // IMPORTANT: If we are using a preset (EmuDeck/RetroDeck), we IGNORE the manual custom paths
        // to ensure the computed paths from the root always take precedence.
        final String? effectiveCustomRoms = (linuxSyncPreset == 'default') ? customRoms : null;
        final String? effectiveCustomEmus = (linuxSyncPreset == 'default') ? customEmus : null;

        romsRootPath = activeLinuxEnvironment.getRomsRoot(home, effectiveCustomRoms, emudeckRootPath);
        emulatorsRootPath = activeLinuxEnvironment.getEmulatorsRoot(home, effectiveCustomEmus, emudeckRootPath);
      } else {
        romsRootPath = _prefs.getString(_romsRootPathKey) ?? p.join(defaultBase, 'ROMs');
        emulatorsRootPath =
            _prefs.getString(_emulatorsRootPathKey) ?? p.join(defaultBase, 'Emulators');
      }

      final romsStatus = await _ensureDirectoryExists(romsRootPath);
      if (romsStatus.hasError) {
        status = romsStatus;
        return status;
      }

      final emusStatus = await _ensureDirectoryExists(emulatorsRootPath);
      if (emusStatus.hasError) {
        status = emusStatus;
        return status;
      }

      loadEmulatorPathOverrides();
      status = const StorageStatus();
      return status;
    } catch (e) {
      status = StorageStatus(error: StorageError.unknown, message: e.toString());
      return status;
    }
  }

  Future<String> getDefaultBase() async {
    final appSupport = await getApplicationSupportDirectory();
    return appSupport.path;
  }

  Future<void> resetRomsRoot() async {
    await _prefs.remove(_romsRootPathKey);
    final base = await getDefaultBase();
    final home = io.Platform.environment['HOME'] ?? '';

    if (defaultTargetPlatform == TargetPlatform.linux) {
      romsRootPath = activeLinuxEnvironment.getRomsRoot(home, null, emudeckRootPath);
    } else {
      romsRootPath = '$base/ROMs';
      }
      status = await _ensureDirectoryExists(romsRootPath);
      }

      Future<void> resetEmulatorsRoot() async {
      await _prefs.remove(_emulatorsRootPathKey);
      final base = await getDefaultBase();
      final home = io.Platform.environment['HOME'] ?? '';

      if (defaultTargetPlatform == TargetPlatform.linux) {
        emulatorsRootPath = activeLinuxEnvironment.getEmulatorsRoot(home, null, emudeckRootPath);
      } else {
        emulatorsRootPath = p.join(base, 'Emulators');
      }
      status = await _ensureDirectoryExists(emulatorsRootPath);
      }
  Future<void> setLinuxSyncPreset(String preset) async {
    await _prefs.setString(_linuxSyncPresetKey, preset);
    linuxSyncPreset = preset;
    // Re-initialize to update paths based on new preset
    await initialize();
  }

  Future<void> setEmudeckRoot(String path) async {
    // If user picked the 'Emulation' folder itself, go up one level
    if (p.basename(path).toLowerCase() == 'emulation') {
      path = p.dirname(path);
    }
    await _prefs.setString(_emudeckRootPathKey, path);
    emudeckRootPath = path;
    // Re-initialize to update paths based on new root
    await initialize();
  }

  void loadEmulatorPathOverrides() {
    for (final key in _prefs.getKeys()) {
      if (key.startsWith('emu_path_')) {
        final emuId = key.replaceFirst('emu_path_', '');
        final path = _prefs.getString(key);
        if (path != null) {
          _emulatorPathOverrides[emuId] = path;
        }
      }
    }
  }

  Future<void> setEmulatorPathOverride(String emulatorId, String path) async {
    await _prefs.setString('emu_path_$emulatorId', path);
    _emulatorPathOverrides[emulatorId] = path;
  }

  Future<String?> getEmulatorUrlOverride(String emulatorId) async {
    return _prefs.getString('emulator_url_override_$emulatorId');
  }

  Future<void> setEmulatorUrlOverride(String emulatorId, String? url) async {
    if (url == null) {
      await _prefs.remove('emulator_url_override_$emulatorId');
    } else {
      await _prefs.setString('emulator_url_override_$emulatorId', url);
    }
  }

  String? getEmulatorPathOverride(String emulatorId) => _emulatorPathOverrides[emulatorId];

  Future<StorageStatus> _ensureDirectoryExists(String path) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        try {
          await directory.create(recursive: true);
        } catch (e) {
          if (e is io.FileSystemException && 
              (e.message.contains('Permission denied') || e.osError?.errorCode == 13)) {
            return StorageStatus(
              error: StorageError.permissionDenied,
              message: 'Permission denied to create or access directory.',
              failedPath: path,
            );
          }
          return StorageStatus(
            error: StorageError.pathNotFound,
            message: 'Path not found or drive disconnected.',
            failedPath: path,
          );
        }
      } else {
        // Double check if we can list it (verifies drive is actually mounted/accessible)
        try {
          await directory.list().first.catchError((_) => Directory(''));
        } catch (e) {
          return StorageStatus(
            error: StorageError.pathNotFound,
            message: 'Directory exists but is not accessible. Drive may be disconnected.',
            failedPath: path,
          );
        }
      }
      return const StorageStatus();
    } catch (e) {
      return StorageStatus(
        error: StorageError.unknown,
        message: e.toString(),
        failedPath: path,
      );
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

  /// Checks if a platform's emulator natively supports ZIP or 7Z archives.
  bool platformSupportsArchive(String? platformSlug) {
    if (platformSlug == null) return false;
    final extensions = _platformExtensions[platformSlug.toLowerCase()] ?? [];
    return extensions.any((ext) => ext.toLowerCase() == '.zip' || ext.toLowerCase() == '.7z');
  }

  Future<String> getRomsDirectory() async => romsRootPath;

  Future<Set<String>> getAllDownloadedFileNames() async {
    final Set<String> downloaded = {};
    try {
      final romsDir = Directory(await getRomsDirectory());
      if (!await romsDir.exists()) return downloaded;
      
      await for (final platformDir in romsDir.list()) {
        if (platformDir is! Directory) continue;
        await for (final entity in platformDir.list()) {
          final name = p.basename(entity.path);
          downloaded.add(name.toLowerCase());
        }
      }
    } catch (_) {}
    return downloaded;
  }

  Future<Map<String, Set<String>>> getAllDownloadedFileNamesByPlatform() async {
    final Map<String, Set<String>> platformMap = {};
    try {
      final romsDir = Directory(await getRomsDirectory());
      if (!await romsDir.exists()) return platformMap;
      
      await for (final platformDir in romsDir.list()) {
        if (platformDir is! Directory) continue;
        final platformSlug = p.basename(platformDir.path);
        final Set<String> downloaded = {};
        await for (final entity in platformDir.list()) {
          final name = p.basename(entity.path);
          downloaded.add(name.toLowerCase());
        }
        platformMap[platformSlug] = downloaded;
      }
    } catch (_) {}
    return platformMap;
  }

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

  /// Tries to find the actual ROM file on disk.
  /// First checks the exact path, then tries common extensions for the platform.
  /// Returns the found path or null if not found.
  Future<String?> findExistingRomPath(Game game, {FileSystemIndex? index}) async {
    final romDir = await getRomDirectory(game);
    final platformLower = game.platformSlug?.toLowerCase();
    
    debugPrint('[Matching] Searching for ${game.name} (Platform: $platformLower) in $romDir');

    // Names to check (in order of priority)
    final namesToCheck = <String>[];
    if (game.fsName != null) namesToCheck.add(game.fsName!);
    if (game.fileName != null) namesToCheck.add(game.fileName!);
    
    final sanitizedName = game.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    namesToCheck.add(sanitizedName);

    // 1. Check using Index if provided (Case-Insensitive & Fast)
    if (index != null && (index.rootPath == romDir || index.rootPath == p.join(romDir, 'roms'))) {
      for (final name in namesToCheck) {
        final lowerName = name.toLowerCase();
        
        // Try exact name match (files)
        if (index.files.containsKey(lowerName)) {
          debugPrint('[Matching] Index hit (file): $lowerName');
          return index.files[lowerName];
        }
        
        // Try name match (dirs)
        if (index.dirs.containsKey(lowerName)) {
          debugPrint('[Matching] Index hit (dir): $lowerName');
          final found = await _findMainRomInFolder(game, index.dirs[lowerName]!);
          if (found != null) return found;
        }

        // Try with extensions
        final extensions = _platformExtensions[platformLower] ?? [];
        for (final ext in extensions) {
          final nameWithExt = lowerName.endsWith(ext.toLowerCase()) ? lowerName : '$lowerName${ext.toLowerCase()}';
          if (index.files.containsKey(nameWithExt)) return index.files[nameWithExt];
        }
      }
      
      // Fuzzy match in index (Last resort, only if name is very similar and not ambiguous)
      for (final name in namesToCheck) {
        final lowerName = name.toLowerCase();
        for (final entry in index.files.entries) {
          // Strict startsWith: only if the match is very close (e.g. adding a small suffix)
          if (entry.key.startsWith(lowerName) && entry.key.length < lowerName.length + 5 && !entry.key.endsWith('.part')) {
            // debugPrint('[Matching] Strict startsWith hit: ${entry.key}');
            return entry.value;
          }
        }
      }
    }

    // 2. Fallback to manual scanning (Legacy/Direct)
    final baseName = game.fsName ?? game.fileName ?? sanitizedName;
    
    // Check exact path first (Case-sensitive check)
    final exactPath = p.join(romDir, baseName);
    if (await File(exactPath).exists()) return p.absolute(exactPath);
    
    // Case-insensitive check by scanning parent directory manually if index not available
    final parentDir = Directory(romDir);
    if (await parentDir.exists()) {
      try {
        await for (final entity in parentDir.list()) {
          final fname = p.basename(entity.path);
          if (fname.toLowerCase() == baseName.toLowerCase()) {
            if (entity is File) return p.absolute(entity.path);
            if (entity is Directory) {
              final found = await _findMainRomInFolder(game, entity.path);
              if (found != null) return found;
            }
          }
        }
      } catch (_) {}
    }

    // 3. Search for multi-file folder (sanitized game name)
    final folderName = sanitizedName;
    final searchDirs = [romDir, p.join(romDir, 'roms')];
    
    for (final dirPath in searchDirs) {
      final pDir = Directory(dirPath);
      if (!await pDir.exists()) continue;

      // Check direct folder match (Case-insensitive)
      try {
        await for (final entity in pDir.list()) {
          if (entity is Directory) {
            final dName = p.basename(entity.path);
            if (dName.toLowerCase() == folderName.toLowerCase()) {
              final found = await _findMainRomInFolder(game, entity.path);
              if (found != null) return found;
            }
          }
        }
      } catch (_) {}
    }

    // 4. Try common extensions for this platform (Case-insensitive)
    final extensions = _platformExtensions[platformLower] ?? [];
    for (final dirPath in searchDirs) {
      final pDir = Directory(dirPath);
      if (!await pDir.exists()) continue;
      
      try {
        final List<FileSystemEntity> entities = await pDir.list().toList();
        for (final ext in extensions) {
          for (final entity in entities) {
            if (entity is File) {
              final fname = p.basename(entity.path).toLowerCase();
              final target = '$baseName$ext'.toLowerCase();
              if (fname == target || fname == baseName.toLowerCase()) {
                return p.absolute(entity.path);
              }
            }
          }
        }
      } catch (_) {}
    }

    // 5. Scan directory for fuzzy file match
    for (final dirPath in searchDirs) {
      final pDir = Directory(dirPath);
      if (!await pDir.exists()) continue;

      try {
        await for (final entity in pDir.list()) {
          if (entity is File) {
            final fname = p.basename(entity.path).toLowerCase();
            final target = baseName.toLowerCase();
            if (fname == target || fname == '$target.iso' || fname == '$target.bin' || fname == '$target.pkg') {
              return p.absolute(entity.path);
            }
          }
        }
      } catch (_) {}
    }

    debugPrint('[Matching] No match found for ${game.name}');
    return null;
  }

  /// Finds the largest ROM-like file in a folder.
  Future<String?> _findMainRomInFolder(Game game, String folderPath) async {
    final platform = game.platformSlug?.toLowerCase() ?? '';
    final isFolderBased = ['windows', 'pc', 'win', 'ps3', 'switch', 'nintendo-switch'].contains(platform);
    if (isFolderBased) {
      // For folder-based platforms, we can often just return the folder path if it's a direct match
      // But we still try to find a "main" file inside first for better emulator compatibility
    }

    final extensions = _platformExtensions[game.platformSlug?.toLowerCase()] ?? [];
    
    File? largestFile;
    int largestSize = 0;

    try {
      await for (final entity in Directory(folderPath).list(recursive: true)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          // Filter by platform extensions if available, or just take any significant file
          if (extensions.isEmpty || extensions.contains(ext)) {
            final size = await entity.length();
            if (size > largestSize) {
              largestSize = size;
              largestFile = entity;
            }
          }
        }
      }
    } catch (_) {}

    if (largestFile != null) {
      return p.absolute(largestFile.path);
    }
    
    // Fallback for PS3/Switch folders that might not have a "known" extension but are valid
    if (isFolderBased) return p.absolute(folderPath);
    
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

    final dirPath = p.join(emulatorsRootPath, emulatorId);
    await _ensureDirectoryExists(dirPath);
    return dirPath;
  }

  Future<String> getEmulatorAppSupportDirectory(String emulatorName, {String? platformSlug}) async {
    if (io.Platform.isMacOS) {
      final appSupport = await getApplicationSupportDirectory();
      // On macOS, getApplicationSupportDirectory() returns ~/Library/Application Support/com.abduznik.freegosy
      // We want ~/Library/Application Support/emulatorName
      return p.join(appSupport.parent.parent.path, 'Application Support', emulatorName);
    } else if (io.Platform.isWindows) {
      final appData = io.Platform.environment['APPDATA'] ?? '';
      return p.join(appData, emulatorName);
    } else if (io.Platform.isLinux) {
      final home = io.Platform.environment['HOME'] ?? '';
      return activeLinuxEnvironment.getEmulatorAppSupportDirectory(home, emulatorName, emudeckRootPath, platformSlug: platformSlug);
    }
    throw UnsupportedError('Platform not supported for save path resolution');
  }

  Future<String> getEmulatorBiosDirectory(String emulatorId, {String? platformSlug}) async {
    if (io.Platform.isLinux) {
      final home = io.Platform.environment['HOME'] ?? '';
      return activeLinuxEnvironment.getBiosPath(home, emudeckRootPath);
    }
    final emuDir = await getEmulatorDirectory(emulatorId);
    final dirPath = p.join(emuDir, 'BIOS');
    await _ensureDirectoryExists(dirPath);
    return dirPath;
  }

  Future<String> getEmulatorSystemDirectory(String emulatorId, {String? platformSlug}) async {
    return await getEmulatorBiosDirectory(emulatorId, platformSlug: platformSlug);
  }

  Future<void> deleteEmulator(String emulatorId) async {
    final dirPath = await getEmulatorDirectory(emulatorId);
    final directory = io.Directory(dirPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
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

    // 1. Direct match (absolute or relative to emulatorDir)
    final direct = File(p.join(emulatorDir, executableName));
    if (await direct.exists()) {
      return direct.path;
    }

    // Try with .exe on Windows
    if (io.Platform.isWindows && !executableName.toLowerCase().endsWith('.exe')) {
      final withExe = File(p.join(emulatorDir, '$executableName.exe'));
      if (await withExe.exists()) {
        return withExe.path;
      }
    }

    if (io.Platform.isLinux) {
      final envPath = await activeLinuxEnvironment.findExecutable(emulatorId, executableName, emulatorsRootPath, emudeckRootPath);
      if (envPath != null) return envPath;
    }

    if (executableName.contains('/')) {
      final parts = executableName.split('/');
      final firstPart = parts.first; // e.g. "PCSX2.app"
      final remaining = parts.sublist(1).join('/'); // e.g. "Contents/MacOS/PCSX2"

      // Recursive search for the bundle directory (max 3 levels)
      await for (final entity in dir.list(recursive: true)) {
        if (entity is Directory) {
          final dirName = p.basename(entity.path);
          
          // Exact match or fuzzy match for versioned .app bundles (e.g. PCSX2-v2.6.3.app matches PCSX2.app)
          bool matches = dirName.toLowerCase() == firstPart.toLowerCase();
          if (!matches && firstPart.toLowerCase().endsWith('.app') && dirName.toLowerCase().endsWith('.app')) {
            final stem = firstPart.substring(0, firstPart.length - 4).toLowerCase();
            if (dirName.toLowerCase().startsWith(stem)) {
              matches = true;
            }
          }

          if (matches) {
            debugPrint("[DirectoryService] Found matching .app bundle: $dirName at ${entity.path}");
            final sub = File(p.join(entity.path, remaining));
            if (await sub.exists()) {
              debugPrint("[DirectoryService] Found direct binary: ${sub.path}");
              return sub.path;
            }
            
            // Secondary check: search inside Contents/MacOS case-insensitively
            final macosDir = Directory(p.join(entity.path, 'Contents', 'MacOS'));
            if (await macosDir.exists()) {
              final binaryName = remaining.split('/').last.toLowerCase();
              debugPrint("[DirectoryService] Searching for binary '$binaryName' in ${macosDir.path}");
              await for (final subEntity in macosDir.list()) {
                if (subEntity is File) {
                  final subName = p.basename(subEntity.path).toLowerCase();
                  if (subName == binaryName) {
                    debugPrint("[DirectoryService] Found binary via case-insensitive match: ${subEntity.path}");
                    return subEntity.path;
                  }
                }
              }
              
              // Third check: find any file in Contents/MacOS (fallback)
              await for (final subEntity in macosDir.list()) {
                if (subEntity is File) {
                  final subName = p.basename(subEntity.path).toLowerCase();
                  final stem = dirName.toLowerCase().replaceAll('.app', '');
                  if (subName.contains(stem) || stem.contains(subName)) {
                    debugPrint("[DirectoryService] Found binary via stem match: ${subEntity.path}");
                    return subEntity.path;
                  }
                }
              }
              // Last resort: return the first file in Contents/MacOS
              await for (final subEntity in macosDir.list()) {
                if (subEntity is File) {
                   debugPrint("[DirectoryService] Using first binary found as last resort: ${subEntity.path}");
                   return subEntity.path;
                }
              }
            }
          }
        }
      }
    }

    // 3. Fallback: Recursive search for the binary (important for Windows "publish" subfolders)
    debugPrint("[DirectoryService] Starting recursive search for $executableName in $emulatorDir");
    int count = 0;
    await for (final entity in dir.list(recursive: true)) {
      count++;
      if (entity is File) {
        final fileName = p.basename(entity.path).toLowerCase();
        final searchName = executableName.toLowerCase();
        
        if (fileName == searchName) {
          debugPrint("[DirectoryService] Found binary via recursive search: ${entity.path}");
          return entity.path;
        }
        
        if (io.Platform.isWindows && !searchName.endsWith('.exe')) {
           if (fileName == '$searchName.exe') {
             debugPrint("[DirectoryService] Found binary via recursive search (with .exe): ${entity.path}");
             return entity.path;
           }
        }
      }
    }
    debugPrint("[DirectoryService] Recursive search finished. Scanned $count entities. Not found.");

    // Secondary check for core libraries if binary not found
    final ext = io.Platform.isMacOS ? '.dylib' : (io.Platform.isWindows ? '.dll' : '.so');
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final name = p.basename(entity.path).toLowerCase();
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

  bool isEmuLaunchScript(String path) {
    return p.basename(path) == 'emu-launch.sh';
  }

  Future<void> launchGame(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
    debugPrint('[DirectoryService] Launching $emulatorId with $romPath');
    if (io.Platform.isLinux) {
      await activeLinuxEnvironment.launch(game, romPath, emulatorId, exePath, args: args);
    } else {
      final exeDir = io.File(exePath).parent.path;
      if (io.Platform.isWindows) {
        final absExe = p.absolute(exePath).replaceAll('/', '\\');
        final absRom = p.absolute(romPath).replaceAll('/', '\\');
        final absDir = p.absolute(exeDir).replaceAll('/', '\\');
        
        debugPrint('[DirectoryService] Windows Launch: $absExe ${args.join(' ')} $absRom (WorkingDir: $absDir)');
        
        await Process.start(
          absExe, 
          [...args, absRom], 
          mode: io.ProcessStartMode.detached,
          workingDirectory: absDir,
          runInShell: false,
        );
      } else if (io.Platform.isMacOS && exePath.contains('.app/')) {
        // Find the .app bundle path
        final parts = exePath.split('/');
        final appIdx = parts.indexWhere((p) => p.endsWith('.app'));
        final appBundlePath = parts.sublist(0, appIdx + 1).join('/');
        
        debugPrint('[DirectoryService] macOS App Launch: open -a "$appBundlePath" --args ${args.join(' ')} "$romPath"');
        
        // Launch via 'open' to ensure macOS environment handles the bundle correctly.
        // Arguments to the binary itself must come after '--args'.
        await Process.run('open', ['-a', appBundlePath, '--args', ...args, romPath]);
      } else {
        debugPrint('[DirectoryService] Unix/macOS Binary Launch: $exePath ${args.join(' ')} $romPath');
        await Process.start(
          exePath, 
          [...args, romPath], 
          mode: io.ProcessStartMode.detached,
        );
      }
    }
  }

  Future<Process?> launchGameWithHandle(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
    debugPrint('[DirectoryService] Launching with handle: $emulatorId with $romPath');
    if (io.Platform.isLinux) {
      return await activeLinuxEnvironment.launchWithHandle(game, romPath, emulatorId, exePath, args: args);
    } else {
      final exeDir = io.File(exePath).parent.path;
      if (io.Platform.isWindows) {
        final absExe = p.absolute(exePath).replaceAll('/', '\\');
        final absRom = p.absolute(romPath).replaceAll('/', '\\');
        final absDir = p.absolute(exeDir).replaceAll('/', '\\');
        
        debugPrint('[DirectoryService] === WINDOWS PROCESS START ===');
        debugPrint('[DirectoryService] Raw Exe: $exePath');
        debugPrint('[DirectoryService] Raw Rom: $romPath');
        debugPrint('[DirectoryService] Abs Exe: $absExe');
        debugPrint('[DirectoryService] Abs Rom: $absRom');
        debugPrint('[DirectoryService] Working Dir: $absDir');

        final process = await Process.start(
          absExe, 
          [...args, absRom], 
          mode: io.ProcessStartMode.normal,
          workingDirectory: absDir,
          runInShell: false,
        );
        
        // IMPORTANT: Drain stdout/stderr to prevent the process from hanging when buffers are full.
        process.stdout.listen((_) {}, onDone: () {}, onError: (_) {});
        process.stderr.listen((_) {}, onDone: () {}, onError: (_) {});
        
        return process;
      } else if (io.Platform.isMacOS && exePath.contains('.app/')) {
        debugPrint('[DirectoryService] macOS App Handle Launch (via binary): $exePath ${args.join(' ')} $romPath');
        // Note: For handles, we stick to direct execution as 'open' doesn't return child PID.
        return await Process.start(
          exePath, 
          [...args, romPath], 
          mode: io.ProcessStartMode.normal,
        );
      } else {
        debugPrint('[DirectoryService] Unix/macOS Binary Handle Launch: $exePath ${args.join(' ')} $romPath');
        return await Process.start(
          exePath, 
          [...args, romPath], 
          mode: io.ProcessStartMode.normal,
        );
      }
    }
  }

  Future<void> launchStandalone(String emulatorId, String exePath, {List<String> args = const []}) async {
    if (io.Platform.isLinux) {
      await activeLinuxEnvironment.launchStandalone(emulatorId, exePath, args: args);
    } else {
      if (io.Platform.isMacOS) {
        // Find the .app bundle path
        final parts = exePath.split('/');
        final appIdx = parts.indexWhere((p) => p.endsWith('.app'));
        if (appIdx != -1) {
          final appBundlePath = parts.sublist(0, appIdx + 1).join('/');
          if (await Directory(appBundlePath).exists()) {
            await io.Process.run('open', [appBundlePath]);
            return;
          }
        }
      }

      final exeDir = File(exePath).parent.path;
      if (io.Platform.isWindows) {
        final normalizedExe = exePath.replaceAll('/', '\\');
        final normalizedDir = exeDir.replaceAll('/', '\\');
        await Process.start(normalizedExe, args, mode: io.ProcessStartMode.detached, workingDirectory: normalizedDir);
      } else {
        await Process.start(exePath, args, mode: io.ProcessStartMode.detached, workingDirectory: exeDir);
      }
    }
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
