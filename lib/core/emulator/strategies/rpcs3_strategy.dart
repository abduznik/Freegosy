import 'dart:io';
import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class Rpcs3Strategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  Rpcs3Strategy(this._directoryService);

  @override
  String get name => 'RPCS3';

  @override
  String get emulatorId => 'rpcs3';

  @override
  List<String> get supportedSlugs => ['ps3', 'playstation-3', 'playstation3'];

  @override
  String get windowsExecutable => 'rpcs3.exe';

  @override
  String get linuxExecutable => 'rpcs3.AppImage';

  @override
  String get macosExecutable => 'RPCS3.app/Contents/MacOS/RPCS3';

  @override
  bool get supportsSaveSync => true;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    
    final normalizedRomPath = p.normalize(romPath);
    if (io.Platform.isLinux && _directoryService.isEmuLaunchScript(exePath)) {
      await Process.start('bash', [exePath, '-e', 'rpcs3', normalizedRomPath], mode: ProcessStartMode.detached);
    } else if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      await Process.start('bash', [exePath, normalizedRomPath], mode: ProcessStartMode.detached);
    } else {
      await Process.start(exePath, [normalizedRomPath], mode: ProcessStartMode.detached);
    }
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    
    final normalizedRomPath = p.normalize(romPath);
    if (io.Platform.isLinux && _directoryService.isEmuLaunchScript(exePath)) {
      return await Process.start('bash', [exePath, '-e', 'rpcs3', normalizedRomPath], mode: ProcessStartMode.normal);
    } else if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      return await Process.start('bash', [exePath, normalizedRomPath], mode: ProcessStartMode.normal);
    } else {
      return await Process.start(exePath, [normalizedRomPath], mode: ProcessStartMode.normal);
    }
  }

  @override
  Future<void> launchStandalone() async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    if (io.Platform.isLinux && _directoryService.isEmuLaunchScript(exePath)) {
      await Process.start('bash', [exePath, '-e', 'rpcs3'], mode: ProcessStartMode.detached);
      return;
    } else if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      await Process.start('bash', [exePath], mode: ProcessStartMode.detached);
      return;
    }

    if (io.Platform.isMacOS) {
      // Find the .app bundle path
      final parts = exePath.split('/');
      final appIdx = parts.indexWhere((p) => p.endsWith('.app'));
      if (appIdx != -1) {
        final appBundlePath = parts.sublist(0, appIdx + 1).join('/');
        if (await io.Directory(appBundlePath).exists()) {
          await io.Process.run('open', [appBundlePath]);
          return;
        }
      }
    }

    final exeDir = File(exePath).parent.path;
    await Process.start(exePath, [], mode: ProcessStartMode.detached, workingDirectory: exeDir);
  }

  @override
  String resolveSavePath(Game game) => '';
}
