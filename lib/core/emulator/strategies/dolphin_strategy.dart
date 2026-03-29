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
  String get linuxExecutable => 'dolphin-emu';

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
    await Process.start(
      exePath,
      ['-b', '-e', romPath],
      mode: ProcessStartMode.detached,
    );
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
    return await Process.start(
      exePath,
      ['-b', '-e', romPath],
      mode: ProcessStartMode.normal,
    );
  }

  @override
  Future<void> launchStandalone() async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    if (io.Platform.isMacOS) {
      // Find the .app bundle path (folder ending in .app containing the executable)
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

    String? workingDir;
    if (io.Platform.isMacOS) {
      workingDir = File(exePath).parent.path;
    }

    await Process.start(exePath, [], mode: ProcessStartMode.detached, workingDirectory: workingDir);
  }

  @override
  String resolveSavePath(Game game) {
    return ''; // Placeholder
  }
}
