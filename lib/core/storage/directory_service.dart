import 'dart:io' as io;
import 'dart:io' show Directory, File, Process;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'app_path_resolver.dart';
import 'app_preferences.dart';
import 'flutter_app_path_resolver.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/rom_constants.dart';
import 'package:freegosy/core/storage/file_system_index.dart';
import 'package:freegosy/core/storage/rom_lookup_service.dart';
import 'package:freegosy/core/emulator/linux_strategies/linux_environment_strategy.dart';
import 'package:freegosy/core/emulator/linux_strategies/native_linux_strategy.dart';
import 'package:freegosy/core/emulator/linux_strategies/emudeck_strategy.dart';
import 'package:freegosy/core/emulator/linux_strategies/retrodeck_strategy.dart';
import 'package:freegosy/core/platform/platform_info.dart';

class DirectoryService {
  static const Map<String, String> platformFolderCanonicalMap = {
    'n3ds': '3ds',
    'nintendo-3ds': '3ds',
    'nintendo3ds': '3ds',
    'new-nintendo-3ds': '3ds',
    'new-nintendo-3ds-xl': '3ds',
    'megadrive': 'genesis',
    'genesis': 'megadrive',
    'megacd': 'segacd',
    'tg16': 'pcengine',
    'famicom': 'nes',
    'famicom-disk-system': 'fds',
    'fds': 'fds',
    'snesna': 'snes',
    'wonderswancolor': 'wonderswan',
    'n64dd': 'n64',
    'mastersystem': 'sms',
  };

  static const Map<String, String> _emudeckFolderAliases = {
    '3ds': 'n3ds',
    'nintendo-3ds': 'n3ds',
    'nintendo3ds': 'n3ds',
    'new-nintendo-3ds': 'n3ds',
    'new-nintendo-3ds-xl': 'n3ds',
    'genesis': 'megadrive',
    'megadrive': 'megadrive',
    'segacd': 'segacd',
    'megacd': 'segacd',
    'pcengine': 'pcengine',
    'tg16': 'pcengine',
    'sms': 'mastersystem',
    'mastersystem': 'mastersystem',
  };

  static const String _romsRootPathKey = 'romsRootPath';
  static const String _emulatorsRootPathKey = 'emulatorsRootPath';
  static const String _linuxSyncPresetKey = 'linuxSyncPreset';
  static const String _linuxPresetRootKey = 'emudeckRootPath';
  static const String _useFlatEmulatorLayoutKey = 'useFlatEmulatorLayout';

  final AppPreferences _prefs;
  final PlatformInfo _platform;
  final AppPathResolver _pathResolver;
  late String romsRootPath;
  late String emulatorsRootPath;
  String linuxSyncPreset = 'default';
  String? linuxPresetRootPath;
  bool useFlatEmulatorLayout = false;
  final Map<String, String> _emulatorPathOverrides = {};
  final Map<String, String> _emulatorFlatpakOverrides = {};
  StorageStatus status = const StorageStatus();
  
  LinuxEnvironmentStrategy? _linuxStrategy;

  DirectoryService(this._prefs, {PlatformInfo? platform, AppPathResolver? pathResolver})
      : _platform = platform ?? PlatformInfo.current,
        _pathResolver = pathResolver ?? const FlutterAppPathResolver();

  bool get isSteamDeck {
    if (!_platform.isLinux) return false;
    final home = _platform.environment['HOME'] ?? '';
    return home == '/home/deck' || io.Directory('/home/deck').existsSync();
  }

  Future<String?> detectEmuDeckRoot() async {
    final home = _platform.environment['HOME'] ?? '/home/deck';
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
      useFlatEmulatorLayout = _prefs.getBool(_useFlatEmulatorLayoutKey) ?? false;
      
      if (_platform.isLinux && (linuxSyncPreset == 'auto' || linuxSyncPreset == 'default') && linuxPresetRootPath == null) {
          final detectedRoot = await detectEmuDeckRoot();
          if (detectedRoot != null) {
            linuxPresetRootPath = detectedRoot;
            linuxSyncPreset = 'emudeck';
            await _prefs.setString(_linuxSyncPresetKey, 'emudeck');
            await _prefs.setString(_linuxPresetRootKey, linuxPresetRootPath!);
          } else {
            final home = _platform.environment['HOME'] ?? '';
            final retrodeckConfig = p.join(home, '.var', 'app', 'net.retrodeck.retrodeck');
            if (await io.Directory(retrodeckConfig).exists()) {
              linuxSyncPreset = 'retrodeck';
              await _prefs.setString(_linuxSyncPresetKey, 'retrodeck');
            }
          }
      }

      _linuxStrategy = null;
      final String defaultBase = await getDefaultBase();
      final home = _platform.environment['HOME'] ?? '';

      if (_platform.isLinux) {
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
    return _pathResolver.getApplicationSupportPath();
  }

  Future<String?> resolveSevenZipPath() async {
    final tempPath = await _pathResolver.getTemporaryPath();
    final String exeName = _platform.isWindows ? '7zr.exe' : _platform.isLinux ? '7zz-linux' : '7zz';
    final exeFile = io.File(p.join(tempPath, exeName));

    if (!await exeFile.exists()) {
      try {
        final bytes = await _pathResolver.loadAsset('thirdparty/$exeName');
        if (bytes == null) {
          debugPrint('[DirectoryService] No asset bundle available to resolve 7zip');
          return null;
        }
        await exeFile.writeAsBytes(bytes);
        if (!_platform.isWindows) {
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
      if (key.startsWith('emu_flatpak_')) {
        final emuId = key.replaceFirst('emu_flatpak_', '');
        final pkg = _prefs.getString(key);
        if (pkg != null) _emulatorFlatpakOverrides[emuId] = pkg;
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

  Future<void> setEmulatorFlatpakOverride(String emulatorId, String? packageId) async {
    if (packageId == null || packageId.isEmpty) {
      await _prefs.remove('emu_flatpak_$emulatorId');
      _emulatorFlatpakOverrides.remove(emulatorId);
    } else {
      await _prefs.setString('emu_flatpak_$emulatorId', packageId);
      _emulatorFlatpakOverrides[emulatorId] = packageId;
    }
  }

  String? getEmulatorFlatpakOverride(String emulatorId) => _emulatorFlatpakOverrides[emulatorId];

  /// Returns the Flatpak package ID for a built-in emulator, preferring
  /// a user-set override, falling back to auto-detection via the active
  /// Linux environment strategy.
  ///
  /// Only returns a package that is actually installed on the system.
  /// The static known mapping is not used as a fallback to avoid
  /// false-positive "installed" status (issue #39).
  Future<String?> getEffectiveFlatpakPackage(String emulatorId) async {
    // 1. User override (set via Settings > Emulators > [...] > Set Flatpak Package)
    final override = getEmulatorFlatpakOverride(emulatorId);
    if (override != null && override.isNotEmpty) return override;

    // 2. Auto-detect via Linux environment strategy
    //    This runs `flatpak list --app --columns=application` to check
    //    which known emulator Flatpaks are actually installed.
    if (_platform.isLinux) {
      final detected = await activeLinuxEnvironment.detectFlatpakEmulators();
      if (detected.containsKey(emulatorId)) return detected[emulatorId];
    }

    return null;
  }

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

  /// Maps any platform slug variant to a single canonical ROM folder name.
  /// Ensures e.g. "neo-geo", "neogeo", "mvs" all resolve to the same folder.
  static const Map<String, String> _slugToCanonicalFolder = {
    // Nintendo
    '3ds': '3ds', 'n3ds': '3ds', 'nintendo-3ds': '3ds', 'nintendo3ds': '3ds',
    'new-nintendo-3ds': '3ds', 'new-nintendo-3ds-xl': '3ds',
    'gba': 'gba', 'game-boy-advance': 'gba',
    'gbc': 'gbc', 'game-boy-color': 'gbc',
    'gb': 'gb', 'game-boy': 'gb',
    'nds': 'nds', 'nintendo-ds': 'nds', 'ds': 'nds',
    'n64': 'n64', 'nintendo-64': 'n64', 'n64dd': 'n64',
    'snes': 'snes', 'snesna': 'snes', 'sfc': 'snes',
    'nes': 'nes', 'famicom': 'nes',
    'fds': 'fds', 'famicom-disk-system': 'fds',
    'gc': 'gc', 'gamecube': 'gc', 'ngc': 'gc',
    'wii': 'wii',
    'wiiu': 'wiiu', 'wii-u': 'wiiu', 'nintendo-wii-u': 'wiiu', 'nintendo-wiiu': 'wiiu',
    'switch': 'switch', 'nintendo-switch': 'switch', 'ns': 'switch',
    // Sega
    'megadrive': 'megadrive', 'genesis': 'megadrive', 'md': 'megadrive',
    'segacd': 'segacd', 'megacd': 'segacd',
    'mastersystem': 'mastersystem', 'sms': 'mastersystem',
    'gamegear': 'gamegear',
    'saturn': 'saturn',
    'dreamcast': 'dreamcast', 'dc': 'dreamcast',
    // Sony
    'psx': 'psx', 'ps1': 'psx', 'playstation': 'psx',
    'ps2': 'ps2', 'playstation-2': 'ps2', 'playstation2': 'ps2',
    'ps3': 'ps3', 'playstation-3': 'ps3', 'playstation3': 'ps3',
    'psp': 'psp', 'playstation-portable': 'psp',
    // SNK / Arcade
    'neogeo': 'neogeo', 'neo-geo': 'neogeo', 'neogeoaes': 'neogeo', 'neogeomvs': 'neogeo',
    'neo-geo-aes': 'neogeo', 'neo-geo-mvs': 'neogeo', 'mvs': 'neogeo', 'aes': 'neogeo',
    'neogeocd': 'neogeocd', 'neocd': 'neogeocd',
    'ngp': 'ngp', 'ngpc': 'ngp', 'neo-geo-pocket': 'ngp',
    'arcade': 'arcade', 'mame': 'arcade',
    // NEC
    'pcengine': 'pcengine', 'tg16': 'pcengine', 'turbografx16': 'pcengine',
    'turbografx-16': 'pcengine', 'pce': 'pcengine', 'pcenginecd': 'pcengine',
    // Bandai
    'wonderswan': 'wonderswan', 'wonderswancolor': 'wonderswan',
    // PC
    'windows': 'windows', 'pc': 'windows', 'win': 'windows',
  };

  String _resolveFolderName(String platformSlug) {
    final lower = platformSlug.toLowerCase();
    // 1. EmuDeck aliases take precedence (EmuDeck has its own folder conventions)
    if (linuxSyncPreset == 'emudeck') {
      return _emudeckFolderAliases[lower] ?? lower;
    }
    // 2. Canonical slug→folder mapping (applies to all other presets)
    final canonical = _slugToCanonicalFolder[lower];
    if (canonical != null) return canonical;
    // 3. Raw slug as-is (unknown platforms)
    return lower;
  }

  Future<String> getRomDirectory(Game game) async {
    final platformSlug = game.platformSlug ?? 'unknown';
    final folderName = _resolveFolderName(platformSlug);
    final canonicalDirPath = p.join(romsRootPath, folderName);

    // Backwards compatibility: if the canonical folder doesn't exist
    // but the raw-slug folder does, use the raw-slug folder to avoid
    // losing access to already-downloaded ROMs.
    final rawSlugDirPath = p.join(romsRootPath, platformSlug.toLowerCase());
    if (folderName != platformSlug.toLowerCase() &&
        !await io.Directory(canonicalDirPath).exists() &&
        await io.Directory(rawSlugDirPath).exists()) {
      return rawSlugDirPath;
    }

    await _ensureDirectoryExists(canonicalDirPath);
    return canonicalDirPath;
  }

  Future<String> getRomFilePath(Game game) async {
    final romDir = await getRomDirectory(game);
    final baseName = game.fsName ?? game.fileName ?? game.name.replaceAll(RegExp(r'[<>:"/\\|?]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    // RomM's `fs_name` is the bare filename without its extension; `fs_extension`
    // is reported separately and must be appended, or the file lands on disk
    // with no extension (e.g. PS2 .iso, NDS .nds) even though fs_extension is
    // populated fine (issue #96 — distinct from the empty-fs_extension case
    // already handled in DownloadService for single-file-foldered games).
    final ext = game.fsExtension;
    final fileName = (ext != null && ext.isNotEmpty && p.extension(baseName).toLowerCase() != '.${ext.toLowerCase()}')
        ? '$baseName.$ext'
        : baseName;
    return p.join(romDir, fileName);
  }

  Future<String?> findExistingRomPath(Game game, {FileSystemIndex? index}) async {
    final romDir = await getRomDirectory(game);
    return RomLookupService.findExistingRomPath(game, romDir, index: index);
  }

  Future<void> setUseFlatEmulatorLayout(bool value) async {
    useFlatEmulatorLayout = value;
    await _prefs.setBool(_useFlatEmulatorLayoutKey, value);
  }

  Future<String> getEmulatorDirectory(String emulatorId) async {
    final override = getEmulatorPathOverride(emulatorId);
    if (override != null) return override;
    final dirPath = useFlatEmulatorLayout
        ? emulatorsRootPath
        : p.join(emulatorsRootPath, emulatorId);
    await _ensureDirectoryExists(dirPath);
    return dirPath;
  }

  Future<String> getEmulatorAppSupportDirectory(String emulatorName, {String? platformSlug}) async {
    if (_platform.isMacOS) {
      final appSupport = await _pathResolver.getApplicationSupportPath();
      return p.join(p.dirname(p.dirname(appSupport)), 'Application Support', emulatorName);
    } else if (_platform.isWindows) {
      final appData = _platform.environment['APPDATA'] ?? '';
      return p.join(appData, emulatorName);
    } else if (_platform.isLinux) {
      final home = _platform.environment['HOME'] ?? '';
      return activeLinuxEnvironment.getEmulatorAppSupportDirectory(home, emulatorName, linuxPresetRootPath, platformSlug: platformSlug);
    }
    throw UnsupportedError('Platform not supported');
  }

  Future<String> getEmulatorBiosDirectory(String emulatorId, {String? platformSlug}) async {
    if (_platform.isLinux) {
      final home = _platform.environment['HOME'] ?? '';
      return activeLinuxEnvironment.getBiosPath(home, linuxPresetRootPath);
    }
    
    final emuDir = await getEmulatorDirectory(emulatorId);
    
    // RetroArch on Windows specifically looks for bios in its 'system' directory, 
    // which is usually next to the executable, but often inside a subfolder like 'RetroArch-Win64'
    if (emulatorId == 'retroarch' && _platform.isWindows) {
      final exePath = await findEmulatorExecutable('retroarch', 'RetroArch.exe');
      if (exePath != null) {
        final systemDir = p.join(io.File(exePath).parent.path, 'system');
        await _ensureDirectoryExists(systemDir);
        return systemDir;
      }
    }
    
    await _ensureDirectoryExists(emuDir);
    return emuDir;
  }

  Future<String> getEmulatorSystemDirectory(String emulatorId, {String? platformSlug}) async => getEmulatorBiosDirectory(emulatorId, platformSlug: platformSlug);

  Future<void> deleteEmulator(String emulatorId) async {
    if (useFlatEmulatorLayout) {
      // In flat layout, emulators are extracted directly into the root
      // without a per-emulator subfolder. Search the root for any directory
      // whose name contains the emulator ID (case-insensitive) and delete it.
      final root = io.Directory(emulatorsRootPath);
      if (!await root.exists()) return;
      try {
        await for (final entity in root.list()) {
          if (entity is io.Directory) {
            final dirName = p.basename(entity.path).toLowerCase();
            if (dirName.contains(emulatorId.toLowerCase())) {
              await entity.delete(recursive: true);
            }
          }
        }
      } catch (_) {}
      return;
    }

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

  /// Finds the emulator executable by [emulatorId] and [executableName].
  ///
  /// Resolution order:
  /// 1. User-set path override (from settings UI, stored as `emu_path_{id}`)
  /// 2. Direct path in emulator directory
  /// 3. Flatpak package override (Linux)
  /// 4. Linux environment-specific detection (EmuDeck, RetroDECK, native)
  /// 5. Recursive search up to 3 levels deep
  /// 6. Nested path fallback for slash-containing names
  ///
  /// The path override (step 1) is critical for Linux where binary names
  /// vary across distros (e.g., `dolphin-emu` vs `dolphin` on Debian).
  /// Users can set the exact binary path in Settings > Emulators.
  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async {
    // Check user-set path override first (set via Settings > Emulators > path override)
    final override = _emulatorPathOverrides[emulatorId];
    if (override != null) {
      if (await File(override).exists()) return override;
      // If override is a directory, look for the executable inside it
      if (await Directory(override).exists()) {
        final candidate = File(p.join(override, executableName));
        if (await candidate.exists()) return candidate.path;
        if (_platform.isWindows && !executableName.toLowerCase().endsWith('.exe')) {
          final withExe = File(p.join(override, '$executableName.exe'));
          if (await withExe.exists()) return withExe.path;
        }
      }
    }

    final emulatorDir = await getEmulatorDirectory(emulatorId);
    final dir = Directory(emulatorDir);
    if (!await dir.exists()) return null;

    // 1. Try direct path
    final direct = File(p.join(emulatorDir, executableName));
    if (await direct.exists()) return direct.path;

    // 2. Try with .exe extension on Windows
    if (_platform.isWindows && !executableName.toLowerCase().endsWith('.exe')) {
      final withExe = File(p.join(emulatorDir, '$executableName.exe'));
      if (await withExe.exists()) return withExe.path;
    }

    // 3. Check for user-set Flatpak package override
    if (_platform.isLinux) {
      final flatpakPkg = await getEffectiveFlatpakPackage(emulatorId);
      if (flatpakPkg != null) {
        return 'flatpak run $flatpakPkg';
      }
    }

    // 4. Environment-specific logic (e.g., Linux Flatpaks auto-detected)
    if (_platform.isLinux) {
      final envPath = await activeLinuxEnvironment.findExecutable(emulatorId, executableName, emulatorsRootPath, linuxPresetRootPath);
      if (envPath != null) return envPath;
    }

    // 5. Handle nested structures (e.g., zip contains a folder like 'RetroArch-Win64/')
    // Search up to 2 levels deep to find the executable
    try {
      final List<io.FileSystemEntity> entities = await dir.list(recursive: true).toList();
      for (final entity in entities) {
        if (entity is io.File) {
          final fileName = p.basename(entity.path);
          if (fileName.toLowerCase() == executableName.toLowerCase() || 
              (_platform.isWindows && fileName.toLowerCase() == '${executableName.toLowerCase()}.exe')) {
            // Check depth
            final relative = p.relative(entity.path, from: emulatorDir);
            final depth = relative.split(_platform.pathSeparator).length;
            if (depth <= 3) { // Root/Subfolder/Executable.exe or Root/Executable.exe
              return entity.path;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DirectoryService] Error during recursive search: $e');
    }

    // 6. Fallback for specifically nested paths in definitions
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
    if (_platform.isLinux) {
      await activeLinuxEnvironment.launch(game, romPath, emulatorId, exePath, args: args);
      return;
    }

    final exeDir = io.File(exePath).parent.path;
    if (_platform.isWindows) {
      await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.detached, workingDirectory: exeDir);
    } else if (_platform.isMacOS) {
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
    if (_platform.isLinux) {
      return await activeLinuxEnvironment.launchWithHandle(game, romPath, emulatorId, exePath, args: args);
    }

    final exeDir = io.File(exePath).parent.path;
    io.Process? process;
    if (_platform.isWindows) {
      process = await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.normal, workingDirectory: exeDir);
    } else if (_platform.isMacOS) {
      if (exePath.contains('.app')) {
        process = await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.normal, workingDirectory: exeDir);
      } else {
        process = await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.normal, workingDirectory: exeDir);
      }
    }
    // CRITICAL: Drain stdout/stderr to prevent pipe buffer deadlock.
    // ProcessStartMode.normal creates pipes for stdout/stderr. If the parent
    // never reads them, the buffer fills up and the child process blocks.
    // This causes emulators (melonDS, DuckStation, RetroArch, etc.) to freeze
    // on launch. The drain() calls consume the output asynchronously.
    // Originally fixed in commit 3a0a4f7, regressed in 97f53a0, restored here.
    // Do NOT remove these drain() calls or change to ProcessStartMode.normal
    // without draining.
    process?.stdout.drain();
    process?.stderr.drain();
    return process;
  }

  Future<void> launchStandalone(String emulatorId, String exePath, {List<String> args = const []}) async {
    if (_platform.isLinux) {
      await activeLinuxEnvironment.launchStandalone(emulatorId, exePath, args: args);
      return;
    }

    final exeDir = io.File(exePath).parent.path;
    if (_platform.isWindows) {
      await io.Process.start(exePath, args, mode: io.ProcessStartMode.detached, workingDirectory: exeDir);
    } else if (_platform.isMacOS) {
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
    final allowed = RomConstants.platformExtensions[platformSlug.toLowerCase()] ?? [];
    if (allowed.isEmpty) return true;
    return allowed.any((v) => v.toLowerCase() == ext);
  }
}
