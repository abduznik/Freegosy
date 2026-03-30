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
  String get linuxExecutable => 'pcsx2-qt';

  @override
  String get macosExecutable => 'PCSX2.app/Contents/MacOS/PCSX2';

  @override
  bool get supportsSaveSync => true;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    
    if (io.Platform.isWindows) {
      final normalizedRom = romPath.replaceAll('/', '\\');
      final normalizedExe = exePath.replaceAll('/', '\\');
      await Process.start(normalizedExe, [normalizedRom], mode: ProcessStartMode.detached);
    } else {
      await Process.start(exePath, [romPath], mode: ProcessStartMode.detached);
    }
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    
    if (io.Platform.isWindows) {
      final normalizedRom = romPath.replaceAll('/', '\\');
      final normalizedExe = exePath.replaceAll('/', '\\');
      return await Process.start(normalizedExe, [normalizedRom], mode: ProcessStartMode.normal);
    } else {
      return await Process.start(exePath, [romPath], mode: ProcessStartMode.normal);
    }
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

    if (io.Platform.isWindows) {
      final normalizedExe = exePath.replaceAll('/', '\\');
      final normalizedDir = exeDir.replaceAll('/', '\\');
      await Process.start(normalizedExe, [], mode: ProcessStartMode.detached, workingDirectory: normalizedDir);
    } else {
      await Process.start(exePath, [], mode: ProcessStartMode.detached, workingDirectory: exeDir);
    }
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
