import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:freegosy/core/romm/romm_models.dart';
import 'linux_environment_strategy.dart';

class NativeLinuxStrategy extends LinuxEnvironmentStrategy {
  // Cache for Flatpak detection — avoids running `flatpak list` repeatedly.
  Map<String, String>? _flatpakCache;

  @override
  String get name => 'Default';

  @override
  String get id => 'default';

  @override
  String getRomsRoot(String home, String? customPath, String? emudeckRoot) {
    return customPath ?? p.join(home, 'ROMs');
  }

  @override
  String getEmulatorsRoot(String home, String? customPath, String? emudeckRoot) {
    return customPath ?? p.join(home, 'Emulators');
  }

  @override
  String getEmulatorAppSupportDirectory(String home, String emulatorName, String? emudeckRoot, {String? platformSlug}) {
    return p.join(home, '.config', emulatorName);
  }

  @override
  String getBiosPath(String home, String? emudeckRoot) {
    return p.join(home, 'Emulators', 'BIOS');
  }

  @override
  Future<String?> findExecutable(String emulatorId, String executableName, String emulatorsRoot, String? emudeckRoot) async {
    // 1. Check direct file
    final direct = io.File(p.join(emulatorsRoot, executableName));
    if (await direct.exists()) return direct.path;

    // 2. Check if a Flatpak is installed for this emulator
    final flatpakPkg = await _flatpakPackageFor(emulatorId);
    if (flatpakPkg != null) {
      // Return the Flatpak command string — the launch method will handle it
      return 'flatpak run $flatpakPkg';
    }

    return null;
  }

  @override
  Future<void> launch(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
    if (exePath.startsWith('flatpak ')) {
      // Flatpak launch: split command, append romPath
      final parts = exePath.split(' ');
      await io.Process.start(
        parts.first,
        [...parts.sublist(1), ...args, romPath],
        mode: io.ProcessStartMode.detached,
      );
    } else if (exePath.endsWith('.sh')) {
      await io.Process.start('bash', [exePath, ...args, romPath], mode: io.ProcessStartMode.detached);
    } else {
      await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.detached);
    }
  }

  @override
  Future<io.Process?> launchWithHandle(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
    if (exePath.startsWith('flatpak ')) {
      final parts = exePath.split(' ');
      return await io.Process.start(
        parts.first,
        [...parts.sublist(1), ...args, romPath],
        mode: io.ProcessStartMode.normal,
      );
    } else if (exePath.endsWith('.sh')) {
      return await io.Process.start('bash', [exePath, ...args, romPath], mode: io.ProcessStartMode.normal);
    } else {
      return await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.normal);
    }
  }

  @override
  Future<void> launchStandalone(String emulatorId, String exePath, {List<String> args = const []}) async {
    if (exePath.startsWith('flatpak ')) {
      final parts = exePath.split(' ');
      await io.Process.start(parts.first, [...parts.sublist(1), ...args],
        mode: io.ProcessStartMode.detached);
    } else if (exePath.endsWith('.sh')) {
      await io.Process.start('bash', [exePath, ...args], mode: io.ProcessStartMode.detached);
    } else {
      final exeDir = io.File(exePath).parent.path;
      await io.Process.start(exePath, args, mode: io.ProcessStartMode.detached, workingDirectory: exeDir);
    }
  }

  /// Returns the Flatpak package ID for [emulatorId], using cached detection.
  Future<String?> _flatpakPackageFor(String emulatorId) async {
    _flatpakCache ??= await detectFlatpakEmulators();
    return _flatpakCache![emulatorId];
  }
}
