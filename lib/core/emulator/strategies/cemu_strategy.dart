import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class CemuStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  CemuStrategy(this._directoryService);

  @override
  String get name => 'Cemu';

  @override
  String get emulatorId => 'cemu';

  @override
  List<String> get supportedSlugs => ['wiiu', 'wii-u', 'nintendo-wii-u', 'nintendo-wiiu'];

  @override
  String get windowsExecutable => 'Cemu.exe';

  @override
  String get linuxExecutable => 'Cemu.AppImage';

  @override
  String get macosExecutable => 'Cemu.app/Contents/MacOS/Cemu';

  @override
  bool get supportsSaveSync => true;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    await _directoryService.launchGame(game, romPath, emulatorId, exePath, args: ['-g']);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    return await _directoryService.launchGameWithHandle(game, romPath, emulatorId, exePath, args: ['-g']);
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
  String resolveSavePath(Game game) => '';
}
