import 'dart:io';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class MelonDSStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  MelonDSStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

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
    // On Linux the active linux strategy (EmuDeck/RetroDeck/Native) handles
    // emu-launch.sh detection and correct launch — delegate to base class.
    if (io.Platform.isLinux) {
      return super.launch(game, romPath);
    }
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    final normalizedRomPath = p.absolute(p.normalize(romPath));
    await preLaunch(game, romPath);
    // melonDS needs its working directory set to find melonDS.ini / firmware
    await Process.start(exePath, [normalizedRomPath],
        workingDirectory: File(exePath).parent.path,
        mode: ProcessStartMode.detached);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    if (io.Platform.isLinux) {
      return super.launchWithHandle(game, romPath);
    }
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    final normalizedRomPath = p.absolute(p.normalize(romPath));
    await preLaunch(game, romPath);
    final process = await Process.start(exePath, [normalizedRomPath],
        workingDirectory: File(exePath).parent.path,
        mode: ProcessStartMode.normal);
    await process.exitCode;
    await postLaunch(game, romPath);
    return process;
  }

  @override
  Future<void> launchStandalone() async {
    if (io.Platform.isLinux) {
      return super.launchStandalone();
    }

    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    if (io.Platform.isMacOS) {
      final parts = exePath.split('/');
      final appIdx = parts.indexWhere((part) => part.endsWith('.app'));
      if (appIdx != -1) {
        final appBundlePath = parts.sublist(0, appIdx + 1).join('/');
        if (await Directory(appBundlePath).exists()) {
          await io.Process.run('open', [appBundlePath]);
          return;
        }
      }
    }

    final exeDir = File(exePath).parent.path;
    await Process.start(exePath, [],
        workingDirectory: exeDir, mode: ProcessStartMode.detached);
  }

  @override
  Future<void> preLaunch(Game game, String romPath) async {
    final srmPath = romPath.replaceAll(RegExp(r'\.[^.]+$'), '.srm');
    final savPath = romPath.replaceAll(RegExp(r'\.[^.]+$'), '.sav');
    final srmFile = File(srmPath);
    if (await srmFile.exists()) {
      await srmFile.copy(savPath);
      debugPrint('[MelonDS-Save] Translated SRM to SAV');
    }
  }

  @override
  Future<void> postLaunch(Game game, String romPath) async {
    final srmPath = romPath.replaceAll(RegExp(r'\.[^.]+$'), '.srm');
    final savPath = romPath.replaceAll(RegExp(r'\.[^.]+$'), '.sav');
    final srmFile = File(srmPath);
    final savFile = File(savPath);
    if (await savFile.exists()) {
      if (!(await srmFile.exists()) ||
          (await savFile.lastModified()).isAfter(await srmFile.lastModified())) {
        await savFile.copy(srmPath);
        debugPrint('[MelonDS-Save] Synced SAV back to SRM');
      }
    }
  }

  @override
  String resolveSavePath(Game game) => '';
}
