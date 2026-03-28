import 'dart:io' as io show Platform, File;
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
      'arcade', 'mame', 'pcengine', 'wonderswan', 'virtualboy', 'msx', 'dos'
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
    'gba': 'mgba_libretro.dll',
    'gbc': 'mgba_libretro.dll',
    'gb': 'mgba_libretro.dll',
    'snes': 'snes9x_libretro.dll',
    'nds': 'desmume2015_libretro.dll',
    'n64': 'mupen64plus_next_libretro.dll',
    'psx': 'pcsx_rearmed_libretro.dll',
    'psp': 'ppsspp_libretro.dll',
    'dc': 'flycast_libretro.dll',
  };

  static const Map<String, String> _coreMapUnix = {
    'gba': 'mgba_libretro.dylib',
    'gbc': 'mgba_libretro.dylib',
    'gb': 'mgba_libretro.dylib',
    'snes': 'snes9x_libretro.dylib',
    'nds': 'desmume2015_libretro.dylib',
    'n64': 'mupen64plus_next_libretro.dylib',
    'psx': 'pcsx_rearmed_libretro.dylib',
    'psp': 'ppsspp_libretro.dylib',
    'dc': 'flycast_libretro.dylib',
  };

  String? _getCoreForSlug(String? slug) {
    if (slug == null) return null;
    final map = io.Platform.isWindows ? _coreMapWindows : _coreMapUnix;
    return map[slug.toLowerCase()];
  }

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
        emulatorId, getExecutableForPlatform());
    if (exePath == null) {
      throw Exception('$name not found. Please download it first.');
    }

    final coreName = _getCoreForSlug(game.platformSlug);
    final sep = io.Platform.isWindows ? r'\' : '/';

    if (coreName == null) {
      await Process.start(exePath, [romPath], mode: ProcessStartMode.detached);
      return;
    }

    final exeDir = io.File(exePath).parent.path;
    final corePath = '$exeDir${sep}cores$sep$coreName';

    if (!await io.File(corePath).exists()) {
      throw MissingRetroArchCoreException(
        coreName: coreName,
        corePath: corePath,
        exePath: exePath,
      );
    }

    await Process.start(
      exePath,
      ['-L', corePath, romPath],
      mode: ProcessStartMode.detached,
    );
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
        emulatorId, getExecutableForPlatform());
    if (exePath == null) {
      throw Exception('$name not found. Please download it first.');
    }

    final coreName = _getCoreForSlug(game.platformSlug);
    final sep = io.Platform.isWindows ? r'\' : '/';

    if (coreName == null) {
      return await Process.start(exePath, [romPath], mode: ProcessStartMode.normal);
    }

    final exeDir = io.File(exePath).parent.path;
    final corePath = '$exeDir${sep}cores$sep$coreName';

    if (!await io.File(corePath).exists()) {
      throw MissingRetroArchCoreException(
        coreName: coreName,
        corePath: corePath,
        exePath: exePath,
      );
    }

    return await Process.start(
      exePath,
      ['-L', corePath, romPath],
      mode: ProcessStartMode.normal,
    );
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
  String resolveSavePath(Game game) {
    return '';
  }
}