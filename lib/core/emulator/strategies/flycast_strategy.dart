import 'dart:io';
import 'dart:io' as io;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class FlycastStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  FlycastStrategy(this._directoryService);

  @override
  String get name => 'Flycast';

  @override
  String get emulatorId => 'flycast';

  @override
  List<String> get supportedSlugs => ['dc', 'dreamcast', 'naomi', 'naomi2', 'atomiswave', 'cave', 'hikaru'];

  @override
  String get windowsExecutable => 'flycast.exe';

  @override
  String get linuxExecutable => 'flycast.AppImage';

  @override
  String get macosExecutable => 'Flycast.app/Contents/MacOS/Flycast';

  @override
  bool get supportsSaveSync => false;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId,
      getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    await Process.start(exePath, [romPath], mode: ProcessStartMode.detached);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId,
      getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    return await Process.start(exePath, [romPath], mode: ProcessStartMode.normal);
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
