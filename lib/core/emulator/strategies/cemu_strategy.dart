import 'dart:io';
import 'dart:io' as io;
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

    if (io.Platform.isLinux && _directoryService.isEmuLaunchScript(exePath)) {
      await Process.start('bash', [exePath, '-e', 'cemu', romPath], mode: ProcessStartMode.detached);
    } else if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      await Process.start('bash', [exePath, romPath], mode: ProcessStartMode.detached);
    } else {
      await Process.start(exePath, ['-g', romPath], mode: ProcessStartMode.detached);
    }
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    if (io.Platform.isLinux && _directoryService.isEmuLaunchScript(exePath)) {
      return await Process.start('bash', [exePath, '-e', 'cemu', romPath], mode: ProcessStartMode.normal);
    } else if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      return await Process.start('bash', [exePath, romPath], mode: ProcessStartMode.normal);
    }
    return await Process.start(exePath, ['-g', romPath], mode: ProcessStartMode.normal);
  }

  @override
  Future<void> launchStandalone() async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    if (io.Platform.isMacOS) {
      // Find the .app bundle path
      final parts = exePath.split('/');
      final appIdx = parts.indexWhere((p) => p.endsWith('.app'));
      if (appIdx != -1) {
        final appBundlePath = parts.sublist(0, appIdx + 1).join('/');
        if (await Directory(appBundlePath).exists()) {
          await io.Process.run('open', [appBundlePath]);
          return;
        }
      }
    }

    final exeDir = File(exePath).parent.path;
    if (io.Platform.isLinux && _directoryService.isEmuLaunchScript(exePath)) {
      await Process.start('bash', [exePath, '-e', 'cemu'], mode: ProcessStartMode.detached, workingDirectory: exeDir);
    } else if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      await Process.start('bash', [exePath], mode: ProcessStartMode.detached, workingDirectory: exeDir);
    } else {
      await Process.start(
        exePath,
        [],
        mode: ProcessStartMode.detached,
        workingDirectory: exeDir,
      );
    }
  }

  @override
  String resolveSavePath(Game game) => '';
}
