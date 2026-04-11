import 'dart:io';
import 'dart:io' as io show Platform;
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
    
    if (io.Platform.isLinux && _directoryService.isEmuLaunchScript(exePath)) {
      await Process.start('bash', [exePath, '-e', 'xemu-emu', '-dvd_path', romPath], mode: ProcessStartMode.detached);
    } else if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      // EmuDeck scripts expect the ROM path directly
      await Process.start('bash', [exePath, romPath], mode: ProcessStartMode.detached);
    } else {
      await Process.start(exePath, ['-dvd_path', romPath], mode: ProcessStartMode.detached);
    }
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    
    if (io.Platform.isLinux && _directoryService.isEmuLaunchScript(exePath)) {
      return await Process.start('bash', [exePath, '-e', 'xemu-emu', '-dvd_path', romPath], mode: ProcessStartMode.normal);
    } else if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      return await Process.start('bash', [exePath, romPath], mode: ProcessStartMode.normal);
    } else {
      return await Process.start(exePath, ['-dvd_path', romPath], mode: ProcessStartMode.normal);
    }
  }

  @override
  Future<void> launchStandalone() async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    
    if (io.Platform.isLinux && _directoryService.isEmuLaunchScript(exePath)) {
      await Process.start('bash', [exePath, '-e', 'xemu-emu'], mode: ProcessStartMode.detached);
      return;
    } else if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      await Process.start('bash', [exePath], mode: ProcessStartMode.detached);
      return;
    }

    final exeDir = File(exePath).parent.path;
    await Process.start(exePath, [], mode: ProcessStartMode.detached, workingDirectory: exeDir);
  }

  @override
  String resolveSavePath(Game game) => '';
}