import 'dart:io' as io;
import 'package:freegosy/core/romm/romm_models.dart';

abstract class LinuxEnvironmentStrategy {
  String get name;
  String get id;

  /// Returns the root ROMs directory for this environment.
  String getRomsRoot(String home, String? customPath, String? emudeckRoot);

  /// Returns the root emulators/tools directory for this environment.
  String getEmulatorsRoot(String home, String? customPath, String? emudeckRoot);

  /// Returns the app support (save/config) directory for a specific emulator.
  String getEmulatorAppSupportDirectory(String home, String emulatorName, String? emudeckRoot, {String? platformSlug});

  /// Returns the BIOS directory for this environment.
  String getBiosPath(String home, String? emudeckRoot);

  /// Tries to find the executable for an emulator.
  Future<String?> findExecutable(String emulatorId, String executableName, String emulatorsRoot, String? emudeckRoot);

  /// Launches a game.
  Future<void> launch(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []});

  /// Launches a game and returns the process handle.
  Future<io.Process?> launchWithHandle(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []});

  /// Launches the emulator standalone.
  Future<void> launchStandalone(String emulatorId, String exePath, {List<String> args = const []});
}
