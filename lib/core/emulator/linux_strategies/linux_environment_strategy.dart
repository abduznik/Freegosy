import 'dart:io' as io;
import 'package:freegosy/core/romm/romm_models.dart';

/// Common Flatpak package IDs mapped to Freegosy emulator IDs.
/// Used by [detectFlatpakEmulators] so we can match installed Flatpaks
/// to built-in emulators automatically.
const Map<String, String> kEmulatorFlatpakPackages = {
  'dolphin': 'org.DolphinEmu.dolphin-emu',
  'retroarch': 'org.libretro.RetroArch',
  'pcsx2': 'net.pcsx2.PCSX2',
  'rpcs3': 'net.rpcs3.RPCS3',
  'duckstation': 'org.duckstation.DuckStation',
  'ppsspp': 'org.ppsspp.PPSSPP',
  'melonds': 'net.kuribo64.melonDS',
  'mgba': 'io.mgba.mGBA',
  'flycast': 'org.flycast.Flycast',
  'cemu': 'info.cemu.Cemu',
  'mame': 'org.mamedev.MAME',
  'xemu': 'app.xemu.xemu',
  'azahar': 'io.github.azahar-emu.azahar',
};

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

  /// Detects installed Flatpak applications and returns a mapping from
  /// Freegosy emulator IDs to the Flatpak package ID.
  ///
  /// Runs `flatpak list --app --columns=application` and matches known
  /// emulator package names from [kEmulatorFlatpakPackages].
  Future<Map<String, String>> detectFlatpakEmulators() async {
    final flatpakMap = <String, String>{};
    try {
      final result = await io.Process.run('flatpak', ['list', '--app', '--columns=application'],
        runInShell: true,
      );
      if (result.exitCode != 0) return flatpakMap;

      final lines = (result.stdout as String).split('\n');
      for (final line in lines) {
        final pkg = line.trim();
        if (pkg.isEmpty) continue;
        // Check if this package matches any known emulator
        for (final entry in kEmulatorFlatpakPackages.entries) {
          if (pkg == entry.value) {
            flatpakMap[entry.key] = pkg;
            break;
          }
        }
      }
    } catch (_) {
      // flatpak not installed or not available — silently ignore
    }
    return flatpakMap;
  }

  /// Returns the Flatpak package ID for a given emulator ID, or null.
  String? getFlatpakPackageForEmulator(String emulatorId) {
    return kEmulatorFlatpakPackages[emulatorId];
  }

  /// Checks whether the `flatpak` command is available on the system.
  Future<bool> isFlatpakAvailable() async {
    try {
      final result = await io.Process.run('which', ['flatpak'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
