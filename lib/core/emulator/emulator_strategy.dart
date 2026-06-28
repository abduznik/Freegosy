import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

abstract class EmulatorStrategy {
  final PlatformInfo _platform;

  EmulatorStrategy({PlatformInfo? platform}) : _platform = platform ?? PlatformInfo.current;

  @protected
  PlatformInfo get platform => _platform;
  String get name;
  String get emulatorId;
  List<String> get supportedSlugs;
  String get windowsExecutable;
  String get linuxExecutable;
  String get macosExecutable => windowsExecutable;
  bool get supportsSaveSync;

  /// The directory service used for finding and launching emulators.
  DirectoryService get directoryService;

  /// Optional arguments to pass when launching the emulator with a game.
  List<String> get launchArgs => [];

  String getExecutableForPlatform() {
    if (_platform.isWindows) return windowsExecutable;
    if (_platform.isLinux) return linuxExecutable;
    if (_platform.isMacOS) return macosExecutable;
    return windowsExecutable;
  }

  Future<String?> findExecutable() async {
    return await directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
  }

  Future<void> launch(Game game, String romPath) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    final normalizedRomPath = p.absolute(p.normalize(romPath));
    await preLaunch(game, romPath);
    await directoryService.launchGame(game, normalizedRomPath, emulatorId, exePath, args: launchArgs);
    await postLaunch(game, romPath);
  }

  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    final normalizedRomPath = p.absolute(p.normalize(romPath));
    await preLaunch(game, romPath);
    final process = await directoryService.launchGameWithHandle(game, normalizedRomPath, emulatorId, exePath, args: launchArgs);
    await process?.exitCode;
    await postLaunch(game, romPath);
    return process;
  }

  Future<void> preLaunch(Game game, String romPath) async {}
  Future<void> postLaunch(Game game, String romPath) async {}

  /// Hook called after the emulator has been downloaded and extracted.
  Future<void> postInstall(String installDir) async {}

  Future<void> launchStandalone() async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    await directoryService.launchStandalone(emulatorId, exePath);
  }

  String resolveSavePath(Game game);
}
