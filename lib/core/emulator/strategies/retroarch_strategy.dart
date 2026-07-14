import 'dart:io' as io;
import 'dart:io' show Process;
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/emulator/retroarch_core_list.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class MissingRetroArchCoreException implements Exception {
  final String coreName;
  final String corePath;
  final String exePath;

  MissingRetroArchCoreException({
    required this.coreName,
    required this.corePath,
    required this.exePath,
  });

  @override
  String toString() => 'Missing RetroArch Core: $coreName at $corePath';
}

class RetroArchStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;
  final Map<String, String> _coreOverrides = {}; // slug -> core base name

  RetroArchStrategy(this._directoryService, {super.platform});

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'RetroArch';

  @override
  String get emulatorId => 'retroarch';

  /// All platform slugs supported by any core in the registry.
  @override
  List<String> get supportedSlugs {
    final slugs = <String>{};
    for (final core in kRetroArchCores) {
      slugs.addAll(core.platforms);
    }
    return slugs.toList();
  }

  @override
  String get windowsExecutable => 'RetroArch.exe';

  @override
  String get linuxExecutable => 'retroarch';

  @override
  String get macosExecutable => 'RetroArch.app/Contents/MacOS/RetroArch';

  @override
  bool get supportsSaveSync => true;

  // ── Core override system ─────────────────────────────────────

  /// Set a core override for a specific platform slug.
  void setCoreOverride(String slug, String coreName) {
    _coreOverrides[slug] = coreName;
    debugPrint('[RetroArch] Core override set: $slug -> $coreName');
  }

  /// Get the current core override for a slug, if any.
  String? getCoreOverride(String slug) => _coreOverrides[slug];

  /// Get all current core overrides.
  Map<String, String> get coreOverrides => Map.unmodifiable(_coreOverrides);

  /// Clear all core overrides.
  void clearCoreOverrides() => _coreOverrides.clear();

  /// Load core overrides from a map (e.g. from SharedPreferences).
  void loadCoreOverrides(Map<String, String> overrides) {
    _coreOverrides
      ..clear()
      ..addAll(overrides);
  }

  /// Backward-compatible NDS core setter.
  void setNdsCore(String core) {
    if (platform.isMacOS && core == 'desmume') {
      debugPrint('[RetroArch] DeSmuME core is not supported on macOS ARM, defaulting to melonDS.');
      setCoreOverride('nds', 'melonds_libretro');
      return;
    }
    final coreId = core == 'desmume' ? 'desmume2015_libretro' : '${core}_libretro';
    setCoreOverride('nds', coreId);
  }

  /// Returns all cores compatible with a given platform slug.
  List<RetroArchCore> getAvailableCoresForSlug(String slug) {
    return getCoresForSlug(slug);
  }

  /// Resolves the core filename for a given platform slug.
  /// Priority: per-platform override -> recommended default.
  String? _getCoreForSlug(String? slug, {String? overrideCoreId}) {
    if (slug == null) return null;

    String baseName = '';

    // 1. Explicit override (per-game or per-platform)
    if (overrideCoreId != null) {
      baseName = coreBaseName(overrideCoreId);
    } else if (_coreOverrides.containsKey(slug.toLowerCase())) {
      baseName = coreBaseName(_coreOverrides[slug.toLowerCase()]!);
    } else {
      // 2. Default from core list
      final defaultCoreId = getDefaultCoreForSlug(slug.toLowerCase());
      if (defaultCoreId != null) {
        baseName = coreBaseName(defaultCoreId);
      }
    }

    if (baseName.isEmpty) return null;

    final ext = platform.isWindows ? 'dll' : (platform.isMacOS ? 'dylib' : 'so');
    return '$baseName.$ext';
  }

  // ── Flatpak support ──────────────────────────────────────────

  static bool _isFlatpakExePath(String exePath) {
    return exePath.startsWith('flatpak run ');
  }

  static String? _flatpakPackageFromExePath(String exePath) {
    if (!_isFlatpakExePath(exePath)) return null;
    final parts = exePath.split(' ');
    if (parts.length < 3) return null;
    return parts.sublist(2).join(' ');
  }

  String? _getFlatpakCoresDir(String exePath) {
    final pkg = _flatpakPackageFromExePath(exePath);
    if (pkg == null) return null;
    final home = platform.environment['HOME'];
    if (home == null) return null;
    return p.join(home, '.var', 'app', pkg, 'config', 'retroarch', 'cores');
  }

  String _getEmuRootDir(String exePath) {
    if (platform.isMacOS && exePath.contains('.app/Contents/MacOS/')) {
      return io.File(exePath).parent.parent.parent.parent.path;
    }
    if (_isFlatpakExePath(exePath)) {
      return '';
    }
    return io.File(exePath).parent.path;
  }

  Future<String?> _resolveCorePath(String exePath, String coreName) async {
    // 1. Check standard emulator directory
    final emuDir = _getEmuRootDir(exePath);
    if (emuDir.isNotEmpty) {
      final standardPath = p.join(emuDir, 'cores', coreName);
      if (await io.File(standardPath).exists()) {
        return standardPath;
      }
    }

    // 2. Check Flatpak data directory
    if (_isFlatpakExePath(exePath)) {
      final flatpakCoresDir = _getFlatpakCoresDir(exePath);
      if (flatpakCoresDir != null) {
        final flatpakPath = p.join(flatpakCoresDir, coreName);
        if (await io.File(flatpakPath).exists()) {
          return flatpakPath;
        }
      }
    }

    // 3. Try to find core in standalone emulator directory
    final underscoreIdx = coreName.indexOf('_');
    if (underscoreIdx != -1) {
      final standaloneEmuId = coreName.substring(0, underscoreIdx);
      final foundPath = await _directoryService.findEmulatorExecutable(standaloneEmuId, coreName);
      if (foundPath != null) {
        return foundPath;
      }
    }

    return null;
  }

  // ── 3DS setup ────────────────────────────────────────────────

  Future<void> _ensure3dsFonts(String citraSystemDir) async {
    final fontFile = io.File(p.join(citraSystemDir, 'sysdata', 'shared_font.bin'));
    if (await fontFile.exists()) return;

    final dio = Dio();
    try {
      await dio.download(
        'https://github.com/citra-emu/citra-sysdata-mks/raw/master/shared_font.bin',
        fontFile.path,
      );
    } catch (e) {
      // ignore
    }
  }

  Future<void> _ensure3dsSetup() async {
    final systemDir = await _directoryService.getEmulatorSystemDirectory('retroarch');
    final citraDir = io.Directory(p.join(systemDir, 'citra'));
    final sysdataDir = io.Directory(p.join(citraDir.path, 'sysdata'));
    final configDir = io.Directory(p.join(citraDir.path, 'config'));

    if (!await citraDir.exists()) await citraDir.create(recursive: true);
    if (!await sysdataDir.exists()) await sysdataDir.create(recursive: true);
    if (!await configDir.exists()) await configDir.create(recursive: true);

    await _ensure3dsFonts(citraDir.path);
  }

  bool _is3dsSlug(String? slug) {
    return ['3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl']
        .contains(slug?.toLowerCase());
  }

  // ── Launch ───────────────────────────────────────────────────

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
        emulatorId, getExecutableForPlatform());
    if (exePath == null) {
      throw Exception('$name not found. Please download it first.');
    }

    final normalizedRomPath = p.absolute(p.normalize(romPath));
    final coreName = _getCoreForSlug(game.platformSlug);

    if (_is3dsSlug(game.platformSlug)) {
      await _ensure3dsSetup();
    }

    if (coreName == null) {
      await _directoryService.launchGame(game, normalizedRomPath, emulatorId, exePath);
      return;
    }

    final corePath = await _resolveCorePath(exePath, coreName);

    if (corePath == null) {
      String expectedPath;
      if (_isFlatpakExePath(exePath)) {
        final flatpakDir = _getFlatpakCoresDir(exePath);
        expectedPath = flatpakDir != null
            ? p.join(flatpakDir, coreName)
            : '$coreName (Flatpak cores dir not found)';
      } else {
        final emuDir = _getEmuRootDir(exePath);
        expectedPath = p.join(emuDir, 'cores', coreName);
      }
      throw MissingRetroArchCoreException(
        coreName: coreName,
        corePath: expectedPath,
        exePath: exePath,
      );
    }

    await _directoryService.launchGame(game, normalizedRomPath, emulatorId, exePath, args: ['-L', corePath]);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath, {String? coreName}) async {
    final exePath = await _directoryService.findEmulatorExecutable(
        emulatorId, getExecutableForPlatform());
    if (exePath == null) {
      throw Exception('$name not found. Please download it first.');
    }

    final normalizedRomPath = p.absolute(p.normalize(romPath));
    final resolvedCoreName = _getCoreForSlug(game.platformSlug, overrideCoreId: coreName);

    if (_is3dsSlug(game.platformSlug)) {
      await _ensure3dsSetup();
    }

    if (resolvedCoreName == null) {
      return await _directoryService.launchGameWithHandle(game, normalizedRomPath, emulatorId, exePath);
    }

    final corePath = await _resolveCorePath(exePath, resolvedCoreName);

    if (corePath == null) {
      String expectedPath;
      if (_isFlatpakExePath(exePath)) {
        final flatpakDir = _getFlatpakCoresDir(exePath);
        expectedPath = flatpakDir != null
            ? p.join(flatpakDir, resolvedCoreName)
            : '$resolvedCoreName (Flatpak cores dir not found)';
      } else {
        final emuDir = _getEmuRootDir(exePath);
        expectedPath = p.join(emuDir, 'cores', resolvedCoreName);
      }
      throw MissingRetroArchCoreException(
        coreName: resolvedCoreName,
        corePath: expectedPath,
        exePath: exePath,
      );
    }

    return await _directoryService.launchGameWithHandle(game, normalizedRomPath, emulatorId, exePath, args: ['-L', corePath]);
  }

  // ── Core download ────────────────────────────────────────────

  Future<void> downloadCore(String coreName, String coresDir, Dio dio) async {
    String url;
    String ext;

    debugPrint('[RetroArch] Downloading core: $coreName to $coresDir');
    debugPrint('[RetroArch] Platform: ${platform.os}');

    final coreBase = coreBaseName(coreName);

    if (platform.isWindows) {
      ext = 'dll';
      url = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/$coreBase.dll.zip';
    } else if (platform.isMacOS) {
      ext = 'dylib';
      bool isArm = io.Platform.version.contains('arm64');
      try {
        final result = Process.runSync('uname', ['-m']);
        if (result.stdout.toString().contains('arm64')) {
          isArm = true;
        }
      } catch (_) {}

      final arch = isArm ? 'arm64' : 'x86_64';
      debugPrint('[RetroArch] Detected macOS architecture: $arch');
      url = 'https://buildbot.libretro.com/nightly/apple/osx/$arch/latest/$coreBase.dylib.zip';

      if (isArm) {
        try {
          await dio.head(url);
        } catch (e) {
          debugPrint('[RetroArch] Core $coreBase not found for arm64, falling back to x86_64');
          url = 'https://buildbot.libretro.com/nightly/apple/osx/x86_64/latest/$coreBase.dylib.zip';
        }
      }
    } else {
      ext = 'so';
      url = 'https://buildbot.libretro.com/nightly/linux/x86_64/latest/$coreBase.so.zip';
    }

    debugPrint('[RetroArch] Target URL: $url');
    debugPrint('[RetroArch] Target Extension: $ext');

    final tempDir = await getTemporaryDirectory();
    final zipPath = p.join(tempDir.path, '$coreName.zip');

    try {
      await dio.download(url, zipPath);
      final bytes = await io.File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      bool found = false;
      for (final entry in archive) {
        debugPrint('[RetroArch] Zip entry: ${entry.name}');
        if (entry.isFile && entry.name.endsWith('.$ext')) {
          final outFile = io.File(p.join(coresDir, entry.name));
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
          debugPrint('[RetroArch] Extracted: ${entry.name} to ${outFile.path}');
          found = true;
        }
      }
      if (!found) {
        debugPrint('[RetroArch] Warning: No file ending in .$ext found in the zip!');
      }
    } finally {
      final f = io.File(zipPath);
      if (await f.exists()) await f.delete();
    }
  }

  @override
  Future<void> launchStandalone() async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    await _directoryService.launchStandalone(emulatorId, exePath);
  }

  @override
  String resolveSavePath(Game game) {
    return '';
  }
}
