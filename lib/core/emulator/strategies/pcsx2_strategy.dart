import 'dart:io';
import 'dart:io' as io;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class Pcsx2Strategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  Pcsx2Strategy(this._directoryService);

  @override
  String get name => 'PCSX2';

  @override
  String get emulatorId => 'pcsx2';

  @override
  List<String> get supportedSlugs => ['ps2', 'playstation-2', 'playstation2'];

  @override
  String get windowsExecutable => 'pcsx2-qt.exe';

  @override
  String get linuxExecutable => 'pcsx2-qt.AppImage';

  @override
  String get macosExecutable => 'PCSX2.app/Contents/MacOS/PCSX2';

  @override
  bool get supportsSaveSync => true;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId,
      getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    await _directoryService.launchGame(game, romPath, emulatorId, exePath);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId,
      getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    return await _directoryService.launchGameWithHandle(
      game,
      romPath,
      emulatorId,
      exePath,
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
    if (io.Platform.isMacOS) {
      final home = io.Platform.environment['HOME'];
      if (home != null) {
        return '$home/Library/Application Support/PCSX2/';
      }
    }
    return '';
  }
}
