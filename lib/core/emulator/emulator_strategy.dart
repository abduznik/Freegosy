import 'dart:io';
import 'dart:io' as io;
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

abstract class EmulatorStrategy {
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
    if (io.Platform.isWindows) return windowsExecutable;
    if (io.Platform.isLinux) return linuxExecutable;
    if (io.Platform.isMacOS) return macosExecutable;
    return windowsExecutable;
  }

  Future<void> launch(Game game, String romPath) async {
    final exePath = await directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    await directoryService.launchGame(game, romPath, emulatorId, exePath, args: launchArgs);
  }

  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    return await directoryService.launchGameWithHandle(game, romPath, emulatorId, exePath, args: launchArgs);
  }

  Future<void> launchStandalone() async {
    final exePath = await directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    await directoryService.launchStandalone(emulatorId, exePath);
  }

  String resolveSavePath(Game game);
}
