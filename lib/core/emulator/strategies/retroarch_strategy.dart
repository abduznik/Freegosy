import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class RetroArchStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  RetroArchStrategy(this._directoryService);

  @override
  String get name => 'RetroArch';

  @override
  String get emulatorId => 'retroarch';

  @override
  List<String> get supportedSlugs => [
        'gba', 'gbc', 'gb', 'nes', 'snes', 'n64', 'nds', 'psx', 'psp',
        'segacd', 'saturn', 'dreamcast', 'megadrive', 'genesis', 'gamegear',
        'atari2600', 'atari7800', 'lynx', 'neogeo', 'arcade', 'mame',
        'pcengine', 'wonderswan', 'virtualboy', 'msx', 'dos'
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
      print('No core mapping for ${game.platformSlug}, launching without core');
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
      throw Exception('Core $coreName not found at $corePath. Please download it in RetroArch first.');
    }

    print('LAUNCHING: $normalizedExe -L $corePath $normalizedRom');
    await Process.start(
      normalizedExe,
      ['-L', corePath, normalizedRom],
      mode: ProcessStartMode.detached,
    );
  }

  @override
  String resolveSavePath(Game game) {
    return '';
  }
}