import 'dart:io' as io show Platform, File, Directory;
import 'dart:io' show Process;
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
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
  String _ndsCore = 'melonds'; // Default NDS core

  RetroArchStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  void setNdsCore(String core) {
    if (io.Platform.isMacOS && core == 'desmume') {
      debugPrint('[RetroArch] DeSmuME core is not supported on macOS ARM, defaulting to melonDS.');
      _ndsCore = 'melonds';
      return;
    }
    _ndsCore = core;
  }

  @override
  String get name => 'RetroArch';

  @override
  String get emulatorId => 'retroarch';

  @override
  List<String> get supportedSlugs => [
      'gba', 'gbc', 'gb', 'nes', 'snes', 'n64', 'nds',
      'psx', 'ps1', 'playstation',
      'psp',
      'segacd', 'saturn',
      'dc', 'dreamcast',
      'megadrive', 'genesis', 'md',
      'gamegear', 'atari2600', 'atari7800', 'lynx', 'neogeo',
      'arcade', 'mame', 'pcengine', 'wonderswan', 'virtualboy', 'msx', 'dos',
      '3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl'
    ];

  @override
  String get windowsExecutable => 'RetroArch.exe';

  @override
  String get linuxExecutable => 'retroarch';

  @override
  String get macosExecutable => 'RetroArch.app/Contents/MacOS/RetroArch';

  @override
  bool get supportsSaveSync => true;

  static const Map<String, String> _coreMap = {
    // Nintendo handhelds
    'gba':         'mgba_libretro',
    'gbc':         'mgba_libretro',
    'gb':          'mgba_libretro',
    'nds':         'melonds_libretro',
    '3ds':         'azahar_libretro',
    'n3ds':        'azahar_libretro',
    'nintendo-3ds':'azahar_libretro',
    'new-nintendo-3ds': 'azahar_libretro',
    'new-nintendo-3ds-xl': 'azahar_libretro',
    'virtualboy':  'mednafen_vb_libretro',
    // Nintendo home
    'nes':         'fceumm_libretro',
    'snes':         'snes9x_libretro',
    'n64':         'mupen64plus_next_libretro',
    // Sony
    'psx':         'pcsx_rearmed_libretro',
    'ps1':         'pcsx_rearmed_libretro',
    'playstation': 'pcsx_rearmed_libretro',
    'psp':         'ppsspp_libretro',
    // Sega
    'megadrive':   'genesis_plus_gx_libretro',
    'genesis':     'genesis_plus_gx_libretro',
    'md':          'genesis_plus_gx_libretro',
    'segacd':      'genesis_plus_gx_libretro',
    'saturn':      'mednafen_saturn_libretro',
    'dc':          'flycast_libretro',
    'dreamcast':   'flycast_libretro',
    'gamegear':    'genesis_plus_gx_libretro',
    // Atari
    'atari2600':   'stella_libretro',
    'atari7800':   'prosystem_libretro',
    'lynx':        'mednafen_lynx_libretro',
    // Arcade / SNK
    'neogeo':      'fbneo_libretro',
    'arcade':      'fbneo_libretro',
    'mame':        'mame_libretro',
    // NEC
    'pcengine':    'mednafen_pce_libretro',
    // Bandai
    'wonderswan':  'mednafen_wswan_libretro',
    // Other
    'msx':         'bluemsx_libretro',
    'dos':         'dosbox_pure_libretro',
  };

  String? _getCoreForSlug(String? slug) {
    if (slug == null) return null;

    final String baseName;
    if (slug.toLowerCase() == 'nds' || slug.toLowerCase() == 'nintendo-ds') {
      baseName = _ndsCore == 'desmume' ? 'desmume2015_libretro' : 'melonds_libretro';
    } else {
      baseName = _coreMap[slug.toLowerCase()] ?? '';
    }

    if (baseName.isEmpty) return null;

    final ext = io.Platform.isWindows ? 'dll' : (io.Platform.isMacOS ? 'dylib' : 'so');
    return '$baseName.$ext';
  }


  String _getEmuRootDir(String exePath) {
    if (io.Platform.isMacOS && exePath.contains('.app/Contents/MacOS/')) {
      // Go up from RetroArch.app/Contents/MacOS/RetroArch to Emulators/retroarch/
      return io.File(exePath).parent.parent.parent.parent.path;
    }
    return io.File(exePath).parent.path;
  }

  Future<String?> _resolveCorePath(String exePath, String coreName) async {
    final emuDir = _getEmuRootDir(exePath);
    final standardPath = p.join(emuDir, 'cores', coreName);

    if (await io.File(standardPath).exists()) {
      return standardPath;
    }

    // Try to find in standalone directory
    // Extract emulatorId from coreName: 'azahar_libretro.dylib' -> 'azahar'
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

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
        emulatorId, getExecutableForPlatform());
    if (exePath == null) {
      throw Exception('$name not found. Please download it first.');
    }

    final normalizedRomPath = p.normalize(romPath);
    final coreName = _getCoreForSlug(game.platformSlug);

    // 1. Check if platform is 3DS-related
    final is3ds = [
      '3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds',
      'new-nintendo-3ds', 'new-nintendo-3ds-xl'
    ].contains(game.platformSlug?.toLowerCase());

    if (is3ds) {
      // 2. Ensure 'citra' exists inside the RetroArch 'system' directory
      await _ensure3dsSetup();
    }

    if (coreName == null) {
      await _directoryService.launchGame(game, normalizedRomPath, emulatorId, exePath);
      return;
    }

    final corePath = await _resolveCorePath(exePath, coreName);

    if (corePath == null) {
      final emuDir = _getEmuRootDir(exePath);
      throw MissingRetroArchCoreException(
        coreName: coreName,
        corePath: p.join(emuDir, 'cores', coreName),
        exePath: exePath,
      );
    }

    await _directoryService.launchGame(game, normalizedRomPath, emulatorId, exePath, args: ['-L', corePath]);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
        emulatorId, getExecutableForPlatform());
    if (exePath == null) {
      throw Exception('$name not found. Please download it first.');
    }

    final normalizedRomPath = p.normalize(romPath);
    final coreName = _getCoreForSlug(game.platformSlug);

    // 1. Check if platform is 3DS-related
    final is3ds = [
      '3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds',
      'new-nintendo-3ds', 'new-nintendo-3ds-xl'
    ].contains(game.platformSlug?.toLowerCase());

    if (is3ds) {
      // 2. Ensure 'citra' exists inside the RetroArch 'system' directory
      await _ensure3dsSetup();
    }

    if (coreName == null) {
      return await _directoryService.launchGameWithHandle(game, normalizedRomPath, emulatorId, exePath);
    }

    final corePath = await _resolveCorePath(exePath, coreName);

    if (corePath == null) {
      final emuDir = _getEmuRootDir(exePath);
      throw MissingRetroArchCoreException(
        coreName: coreName,
        corePath: p.join(emuDir, 'cores', coreName),
        exePath: exePath,
      );
    }

    return await _directoryService.launchGameWithHandle(game, normalizedRomPath, emulatorId, exePath, args: ['-L', corePath]);
  }

  Future<void> downloadCore(String coreName, String coresDir, Dio dio) async {
    String url;
    String ext;
    
    debugPrint('[RetroArch] Downloading core: $coreName to $coresDir');
    debugPrint('[RetroArch] Platform: ${io.Platform.operatingSystem}');

    // Strip any existing extension from coreName to ensure we append the correct one for the URL
    final coreBaseName = p.basenameWithoutExtension(coreName);

    if (io.Platform.isWindows) {
      ext = 'dll';
      url = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/$coreBaseName.dll.zip';
    } else if (io.Platform.isMacOS) {
      ext = 'dylib';
      // Detect if we are on Apple Silicon or Intel
      bool isArm = io.Platform.version.contains('arm64');
      try {
        final result = Process.runSync('uname', ['-m']);
        if (result.stdout.toString().contains('arm64')) {
          isArm = true;
        }
      } catch (_) {}
      
      final arch = isArm ? 'arm64' : 'x86_64';
      debugPrint('[RetroArch] Detected macOS architecture: $arch');
      url = 'https://buildbot.libretro.com/nightly/apple/osx/$arch/latest/$coreBaseName.dylib.zip';

      if (isArm) {
        // Fallback for ARM64: if core is missing, try x86_64
        try {
          await dio.head(url);
        } catch (e) {
          debugPrint('[RetroArch] Core $coreBaseName not found for arm64, falling back to x86_64');
          url = 'https://buildbot.libretro.com/nightly/apple/osx/x86_64/latest/$coreBaseName.dylib.zip';
        }
      }
    } else {
      ext = 'so';
      url = 'https://buildbot.libretro.com/nightly/linux/x86_64/latest/$coreBaseName.so.zip';
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
