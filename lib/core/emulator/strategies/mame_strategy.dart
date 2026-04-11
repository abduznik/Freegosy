import 'dart:io';
import 'dart:io' as io;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class MAMEStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  MAMEStrategy(this._directoryService);

  @override
  String get name => 'MAME';

  @override
  String get emulatorId => 'mame';

  @override
  List<String> get supportedSlugs => ['arcade', 'mame'];

  @override
  String get windowsExecutable => 'mame.exe';

  @override
  String get linuxExecutable => 'mame';

  @override
  bool get supportsSaveSync => false;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    
    if (io.Platform.isLinux) {
      if (_directoryService.isEmuLaunchScript(exePath)) {
        await Process.start('bash', [exePath, '-e', 'mame', romPath], mode: ProcessStartMode.detached);
        return;
      } else if (exePath.endsWith('.sh')) {
        await Process.start('bash', [exePath, romPath], mode: ProcessStartMode.detached);
        return;
      }
    }
    await Process.start(exePath, [romPath], mode: ProcessStartMode.detached);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    
    if (io.Platform.isLinux) {
      if (_directoryService.isEmuLaunchScript(exePath)) {
        return await Process.start('bash', [exePath, '-e', 'mame', romPath], mode: ProcessStartMode.normal);
      } else if (exePath.endsWith('.sh')) {
        return await Process.start('bash', [exePath, romPath], mode: ProcessStartMode.normal);
      }
    }
    return await Process.start(exePath, [romPath], mode: ProcessStartMode.normal);
  }

  @override
  Future<void> launchStandalone() async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    if (io.Platform.isLinux) {
      if (_directoryService.isEmuLaunchScript(exePath)) {
        await Process.start('bash', [exePath, '-e', 'mame'], mode: ProcessStartMode.detached);
        return;
      } else if (exePath.endsWith('.sh')) {
        await Process.start('bash', [exePath], mode: ProcessStartMode.detached);
        return;
      }
    }

    final exeDir = File(exePath).parent.path;
    await Process.start(
      exePath,
      [],
      mode: ProcessStartMode.detached,
      workingDirectory: exeDir,
    );
  }

  @override
  String resolveSavePath(Game game) => '';
}
