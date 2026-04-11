import 'dart:io';
import 'dart:io' as io;
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class AzaharStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  AzaharStrategy(this._directoryService);

  @override
  String get name => 'Azahar';

  @override
  String get emulatorId => 'azahar';

  @override
  List<String> get supportedSlugs => [
    '3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds',
    'new-nintendo-3ds', 'new-nintendo-3ds-xl',
  ];

  @override
  String get windowsExecutable => 'azahar.exe';

  @override
  String get linuxExecutable => 'azahar.AppImage';

  @override
  String get macosExecutable => 'Azahar.app/Contents/MacOS/azahar';

  @override
  bool get supportsSaveSync => true;

  Future<void> _ensure3dsFonts(String azaharSystemDir) async {
    final fontFile = io.File(p.join(azaharSystemDir, 'sysdata', 'shared_font.bin'));
    if (await fontFile.exists()) return;

    final dio = Dio();
    try {
      await dio.download(
        'https://github.com/citra-emu/citra-sysdata-mks/raw/master/shared_font.bin',
        fontFile.path,
      );
    } catch (e) {
      // ignore
    }
  }

  Future<void> _ensure3dsSetup() async {
    final azaharSystemDir = await _directoryService.getEmulatorSystemDirectory(emulatorId);
    final sysdataDir = io.Directory(p.join(azaharSystemDir, 'sysdata'));
    final configDir = io.Directory(p.join(azaharSystemDir, 'config'));

    if (!await sysdataDir.exists()) await sysdataDir.create(recursive: true);
    if (!await configDir.exists()) await configDir.create(recursive: true);

    await _ensure3dsFonts(azaharSystemDir);
  }

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );

    if (exePath == null) throw Exception('$name not found. Please download it first.');

    if (io.Platform.isMacOS) {
      if (exePath.endsWith('.dylib')) {
        throw Exception('Found Azahar Libretro core. Please switch to RetroArch in Settings to play this game.');
      }

      // On macOS, launching via 'open -a App.app --args rom' is much more stable than launching internal binary
      final parts = exePath.split('/');
      final appIdx = parts.indexWhere((p) => p.endsWith('.app'));
      if (appIdx != -1) {
        final appBundlePath = parts.sublist(0, appIdx + 1).join('/');
        if (await Directory(appBundlePath).exists()) {
          await _ensure3dsSetup();
          await io.Process.run('open', [appBundlePath, '--args', romPath]);
          return;
        }
      }
    }

    await _ensure3dsSetup();
    if (io.Platform.isLinux && _directoryService.isEmuLaunchScript(exePath)) {
      await Process.start('bash', [exePath, '-e', 'azahar', romPath], mode: ProcessStartMode.detached);
    } else if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      await Process.start('bash', [exePath, romPath], mode: ProcessStartMode.detached);
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

    if (io.Platform.isMacOS && exePath.endsWith('.dylib')) {
      throw Exception('Found Azahar Libretro core. Please switch to RetroArch in Settings to play this game.');
    }

    await _ensure3dsSetup();
    if (io.Platform.isLinux && _directoryService.isEmuLaunchScript(exePath)) {
      return await Process.start('bash', [exePath, '-e', 'azahar', romPath], mode: ProcessStartMode.normal);
    } else if (io.Platform.isLinux && exePath.endsWith('.sh')) {
      return await Process.start('bash', [exePath, romPath], mode: ProcessStartMode.normal);
    }
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
        if (await io.Directory(appBundlePath).exists()) {
          await io.Process.run('open', [appBundlePath]);
          return;
        }
      }
    }

    final exeDir = io.File(exePath).parent.path;
    if (io.Platform.isLinux && _directoryService.isEmuLaunchScript(exePath)) {
      await Process.start('bash', [exePath, '-e', 'azahar'], mode: ProcessStartMode.detached, workingDirectory: exeDir);
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
