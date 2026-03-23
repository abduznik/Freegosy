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

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(emulatorId, getExecutableForPlatform());
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    await Process.run(exePath, [romPath]);
  }

  @override
  String resolveSavePath(Game game) {
    return ''; // Placeholder
  }
}
