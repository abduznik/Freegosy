import 'dart:io';
import 'dart:io' as io;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class DolphinStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  DolphinStrategy(this._directoryService);

  @override
  String get name => 'Dolphin';

  @override
  String get emulatorId => 'dolphin';

  @override
  List<String> get supportedSlugs => ['gc', 'gamecube', 'wii', 'ngc'];

  @override
  String get windowsExecutable => 'Dolphin.exe';

  @override
  String get linuxExecutable => 'Dolphin.AppImage';

  @override
  String get macosExecutable => 'Dolphin.app/Contents/MacOS/Dolphin';

  @override
  bool get supportsSaveSync => true;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId,
      getExecutableForPlatform(),
    );
    if (exePath == null) {
      throw Exception('$name not found. Please download it first.');
    }

    // Dolphin needs -b -e to launch a game in batch mode and exit on close
    final args = io.Platform.isLinux ? <String>[] : ['-b', '-e'];
    await _directoryService.launchGame(game, romPath, emulatorId, exePath, args: args);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId,
      getExecutableForPlatform(),
    );
    if (exePath == null) {
      throw Exception('$name not found. Please download it first.');
    }

    final args = io.Platform.isLinux ? <String>[] : ['-b', '-e'];
    return await _directoryService.launchGameWithHandle(
      game,
      romPath,
      emulatorId,
      exePath,
      args: args,
    );
  }

  @override
  Future<void> launchStandalone() async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId,
      getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    await _directoryService.launchStandalone(emulatorId, exePath);
  }

  @override
  String resolveSavePath(Game game) {
    return ''; // Placeholder
  }
}
