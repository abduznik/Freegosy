import 'dart:io';
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
  bool get supportsSaveSync => true;

  static const Map<String, String> _coreMap = {
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

  String? _getCoreForSlug(String? slug) {
    if (slug == null) return null;
    return _coreMap[slug.toLowerCase()];
  }

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
        emulatorId, getExecutableForPlatform());
    if (exePath == null) {
      throw Exception('$name not found. Please download it first.');
    }

    final normalizedExe = exePath.replaceAll('/', r'\');
    final normalizedRom = romPath.replaceAll('/', r'\');
    final coreName = _getCoreForSlug(game.platformSlug);

    if (coreName == null) {
      await Process.start(
        normalizedExe,
        [normalizedRom],
        mode: ProcessStartMode.detached,
      );
      return;
    }

    final exeDir = File(normalizedExe).parent.path;
    final corePath = '$exeDir\\cores\\$coreName';

    if (!await File(corePath).exists()) {
      throw MissingRetroArchCoreException(
        coreName: coreName,
        corePath: corePath,
        exePath: normalizedExe,
      );
    }

    await Process.start(
      normalizedExe,
      ['-L', corePath, normalizedRom],
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

    final normalizedExe = exePath.replaceAll('/', r'\');
    final normalizedRom = romPath.replaceAll('/', r'\');
    final coreName = _getCoreForSlug(game.platformSlug);

    if (coreName == null) {
      return await Process.start(
        normalizedExe,
        [normalizedRom],
        mode: ProcessStartMode.normal,
      );
    }

    final exeDir = File(normalizedExe).parent.path;
    final corePath = '$exeDir\\cores\\$coreName';

    if (!await File(corePath).exists()) {
      throw MissingRetroArchCoreException(
        coreName: coreName,
        corePath: corePath,
        exePath: normalizedExe,
      );
    }

    return await Process.start(
      normalizedExe,
      ['-L', corePath, normalizedRom],
      mode: ProcessStartMode.normal,
    );
  }

  Future<void> downloadCore(String coreName, String coresDir, Dio dio) async {
    final url = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/$coreName.zip';
    final tempDir = await getTemporaryDirectory();
    final zipPath = p.join(tempDir.path, '$coreName.zip');

    try {
      await dio.download(url, zipPath);
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive) {
        if (entry.isFile && entry.name.endsWith('.dll')) {
          final outFile = File('$coresDir\\${entry.name}');
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
        }
      }
    } finally {
      final f = File(zipPath);
      if (await f.exists()) await f.delete();
    }
  }

  @override
  String resolveSavePath(Game game) {
    return '';
  }
}