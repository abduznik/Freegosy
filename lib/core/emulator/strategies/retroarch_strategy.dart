import 'dart:io' as io show Platform, File, Directory;
import 'dart:io' show Process, ProcessStartMode;
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

  RetroArchStrategy(this._directoryService);

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

  static const Map<String, String> _coreMapWindows = {
    // Nintendo handhelds
    'gba':         'mgba_libretro.dll',
    'gbc':         'mgba_libretro.dll',
    'gb':          'mgba_libretro.dll',
    'nds':         'desmume2015_libretro.dll',
    '3ds':         'azahar_libretro.dll',
    'n3ds':        'azahar_libretro.dll',
    'nintendo-3ds':'azahar_libretro.dll',
    'new-nintendo-3ds': 'azahar_libretro.dll',
    'new-nintendo-3ds-xl': 'azahar_libretro.dll',
    'virtualboy':  'mednafen_vb_libretro.dll',
    // Nintendo home
    'nes':         'fceumm_libretro.dll',
    'snes':        'snes9x_libretro.dll',
    'n64':         'mupen64plus_next_libretro.dll',
    // Sony
    'psx':         'pcsx_rearmed_libretro.dll',
    'ps1':         'pcsx_rearmed_libretro.dll',
    'playstation': 'pcsx_rearmed_libretro.dll',
    'psp':         'ppsspp_libretro.dll',
    // Sega
    'megadrive':   'genesis_plus_gx_libretro.dll',
    'genesis':     'genesis_plus_gx_libretro.dll',
    'md':          'genesis_plus_gx_libretro.dll',
    'segacd':      'genesis_plus_gx_libretro.dll',
    'saturn':      'mednafen_saturn_libretro.dll',
    'dc':          'flycast_libretro.dll',
    'dreamcast':   'flycast_libretro.dll',
    'gamegear':    'genesis_plus_gx_libretro.dll',
    // Atari
    'atari2600':   'stella_libretro.dll',
    'atari7800':   'prosystem_libretro.dll',
    'lynx':        'mednafen_lynx_libretro.dll',
    // Arcade / SNK
    'neogeo':      'fbneo_libretro.dll',
    'arcade':      'fbneo_libretro.dll',
    'mame':        'mame_libretro.dll',
    // NEC
    'pcengine':    'mednafen_pce_libretro.dll',
    // Bandai
    'wonderswan':  'mednafen_wswan_libretro.dll',
    // Other
    'msx':         'bluemsx_libretro.dll',
    'dos':         'dosbox_pure_libretro.dll',
  };

  static const Map<String, String> _coreMapUnix = {
    // Nintendo handhelds
    'gba':         'mgba_libretro.dylib',
    'gbc':         'mgba_libretro.dylib',
    'gb':          'mgba_libretro.dylib',
    'nds':         'desmume2015_libretro.dylib',
    '3ds':         'azahar_libretro.dylib',
    'n3ds':        'azahar_libretro.dylib',
    'nintendo-3ds':'azahar_libretro.dylib',
    'new-nintendo-3ds': 'azahar_libretro.dylib',
    'new-nintendo-3ds-xl': 'azahar_libretro.dylib',
    'virtualboy':  'mednafen_vb_libretro.dylib',
    // Nintendo home
    'nes':         'fceumm_libretro.dylib',
    'snes':        'snes9x_libretro.dylib',
    'n64':         'mupen64plus_next_libretro.dylib',
    // Sony
    'psx':         'pcsx_rearmed_libretro.dylib',
    'ps1':         'pcsx_rearmed_libretro.dylib',
    'playstation': 'pcsx_rearmed_libretro.dylib',
    'psp':         'ppsspp_libretro.dylib',
    // Sega
    'megadrive':   'genesis_plus_gx_libretro.dylib',
    'genesis':     'genesis_plus_gx_libretro.dylib',
    'md':          'genesis_plus_gx_libretro.dylib',
    'segacd':      'genesis_plus_gx_libretro.dylib',
    'saturn':      'mednafen_saturn_libretro.dylib',
    'dc':          'flycast_libretro.dylib',
    'dreamcast':   'flycast_libretro.dylib',
    'gamegear':    'genesis_plus_gx_libretro.dylib',
    // Atari
    'atari2600':   'stella_libretro.dylib',
    'atari7800':   'prosystem_libretro.dylib',
    'lynx':        'mednafen_lynx_libretro.dylib',
    // Arcade / SNK
    'neogeo':      'fbneo_libretro.dylib',
    'arcade':      'fbneo_libretro.dylib',
    'mame':        'mame_libretro.dylib',
    // NEC
    'pcengine':    'mednafen_pce_libretro.dylib',
    // Bandai
    'wonderswan':  'mednafen_wswan_libretro.dylib',
    // Other
    'msx':         'bluemsx_libretro.dylib',
    'dos':         'dosbox_pure_libretro.dylib',
  };

  String? _getCoreForSlug(String? slug) {
    if (slug == null) return null;
    final map = io.Platform.isWindows ? _coreMapWindows : _coreMapUnix;
    return map[slug.toLowerCase()];
  }

  Future<String?> _resolveCorePath(String exePath, String coreName) async {
    final sep = io.Platform.isWindows ? r'\' : '/';
    final exeDir = io.File(exePath).parent.path;
    final standardPath = '$exeDir${sep}cores$sep$coreName';

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
      await Process.start(exePath, [normalizedRomPath], mode: ProcessStartMode.detached);
      return;
    }

    final corePath = await _resolveCorePath(exePath, coreName);

    if (corePath == null) {
      final sep = io.Platform.isWindows ? r'\' : '/';
      final exeDir = io.File(exePath).parent.path;
      throw MissingRetroArchCoreException(
        coreName: coreName,
        corePath: '$exeDir${sep}cores$sep$coreName',
        exePath: exePath,
      );
    }

    if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      await Process.start(
        'bash',
        [exePath, '-L', corePath, normalizedRomPath],
        mode: ProcessStartMode.detached,
      );
    } else {
      await Process.start(
        exePath,
        ['-L', corePath, normalizedRomPath],
        mode: ProcessStartMode.detached,
      );
    }
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
      if (io.Platform.isLinux && exePath.endsWith('.sh')) {
        return await Process.start('bash', [exePath, normalizedRomPath], mode: ProcessStartMode.normal);
      } else {
        return await Process.start(exePath, [normalizedRomPath], mode: ProcessStartMode.normal);
      }
    }

    final corePath = await _resolveCorePath(exePath, coreName);

    if (corePath == null) {
      final sep = io.Platform.isWindows ? r'\' : '/';
      final exeDir = io.File(exePath).parent.path;
      throw MissingRetroArchCoreException(
        coreName: coreName,
        corePath: '$exeDir${sep}cores$sep$coreName',
        exePath: exePath,
      );
    }

    if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      return await Process.start(
        'bash',
        [exePath, '-L', corePath, normalizedRomPath],
        mode: ProcessStartMode.normal,
      );
    } else {
      return await Process.start(
        exePath,
        ['-L', corePath, normalizedRomPath],
        mode: ProcessStartMode.normal,
      );
    }
  }

  Future<void> downloadCore(String coreName, String coresDir, Dio dio) async {
    final String url;
    final String ext;
    if (io.Platform.isWindows) {
      ext = 'dll';
      url = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/$coreName.zip';
    } else if (io.Platform.isMacOS) {
      ext = 'dylib';
      url = 'https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/$coreName.zip';
    } else {
      ext = 'so';
      url = 'https://buildbot.libretro.com/nightly/linux/x86_64/latest/$coreName.zip';
    }

    final tempDir = await getTemporaryDirectory();
    final zipPath = p.join(tempDir.path, '$coreName.zip');

    try {
      await dio.download(url, zipPath);
      final bytes = await io.File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive) {
        if (entry.isFile && entry.name.endsWith('.$ext')) {
          final outFile = io.File(p.join(coresDir, entry.name));
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
        }
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

    if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      await Process.start('bash', [exePath], mode: ProcessStartMode.detached);
      return;
    }

    if (io.Platform.isMacOS) {
      // Find the .app bundle path
      final parts = exePath.split('/');
      final appIdx = parts.indexWhere((p) => p.endsWith('.app'));
      if (appIdx != -1) {
        final appBundlePath = parts.sublist(0, appIdx + 1).join('/');
        if (await io.Directory(appBundlePath).exists()) {
          await Process.run('open', [appBundlePath]);
          return;
        }
      }
    }

    final exeDir = io.File(exePath).parent.path;
    await Process.start(exePath, [], mode: ProcessStartMode.detached, workingDirectory: exeDir);
  }

  @override
  String resolveSavePath(Game game) {
    return '';
  }
}
