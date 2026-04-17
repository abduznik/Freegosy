import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class XemuStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  XemuStrategy(this._directoryService);

  @override
  String get name => 'Xemu';

  @override
  String get emulatorId => 'xemu';

  @override
  List<String> get supportedSlugs => ['xbox'];

  @override
  String get windowsExecutable => 'xemu.exe';

  @override
  String get linuxExecutable => 'xemu.AppImage';

  @override
  bool get supportsSaveSync => false;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    
    await _directoryService.launchGame(game, romPath, emulatorId, exePath, args: ['-dvd_path']);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    
    return await _directoryService.launchGameWithHandle(game, romPath, emulatorId, exePath, args: ['-dvd_path']);
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