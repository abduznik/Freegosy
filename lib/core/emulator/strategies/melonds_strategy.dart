import 'dart:io';
import 'dart:io' as io;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class MelonDSStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  MelonDSStrategy(this._directoryService);

  @override
  String get name => 'melonDS';

  @override
  String get emulatorId => 'melonds';

  @override
  List<String> get supportedSlugs => ['nds', 'nintendo-ds', 'ds'];

  @override
  String get windowsExecutable => 'melonDS.exe';

  @override
  String get linuxExecutable => 'melonDS';

  @override
  String get macosExecutable => 'melonDS.app/Contents/MacOS/melonDS';

  @override
  bool get supportsSaveSync => true;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId,
      getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      await Process.start('bash', [exePath, romPath], mode: ProcessStartMode.detached);
    } else {
      await Process.start(exePath, [romPath], mode: ProcessStartMode.detached);
    }
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId,
      getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    final workingDir = File(exePath).parent.path;
    final Process process;
    if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      process = await Process.start('bash', [exePath, romPath], workingDirectory: workingDir, mode: ProcessStartMode.normal);
    } else {
      process = await Process.start(exePath, [romPath], workingDirectory: workingDir, mode: ProcessStartMode.normal);
    }
    process.stdout.drain();
    process.stderr.drain();
    return process;
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
    if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      await Process.start('bash', [exePath], workingDirectory: exeDir, mode: ProcessStartMode.detached);
    } else {
      await Process.start(exePath, [], workingDirectory: exeDir, mode: ProcessStartMode.detached);
    }
  }

  @override
  String resolveSavePath(Game game) {
    return ''; // Placeholder
  }
}
