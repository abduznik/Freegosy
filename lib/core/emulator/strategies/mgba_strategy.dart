import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class MGBAStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  MGBAStrategy(this._directoryService);

  @override
  String get name => 'mGBA';

  @override
  String get emulatorId => 'mgba';

  @override
  List<String> get supportedSlugs => ['gba', 'gbc', 'gb', 'game-boy-advance', 'game-boy-color', 'game-boy'];

  @override
  String get windowsExecutable => 'mGBA.exe';

  @override
  String get linuxExecutable => 'mgba';

  @override
  String get macosExecutable => 'mGBA.app/Contents/MacOS/mGBA';

  @override
  bool get supportsSaveSync => false;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    
    await _directoryService.launchGame(game, romPath, emulatorId, exePath);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    
    return await _directoryService.launchGameWithHandle(game, romPath, emulatorId, exePath);
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
