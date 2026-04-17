import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class PPSSPPStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  PPSSPPStrategy(this._directoryService);

  @override
  String get name => 'PPSSPP';

  @override
  String get emulatorId => 'ppsspp';

  @override
  List<String> get supportedSlugs => ['psp', 'playstation-portable'];

  @override
  String get windowsExecutable => 'PPSSPPWindows64.exe';

  @override
  String get linuxExecutable => 'PPSSPP';

  @override
  String get macosExecutable => 'PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL';

  @override
  bool get supportsSaveSync => true;

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
