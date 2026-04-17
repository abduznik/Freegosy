import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:freegosy/core/romm/romm_models.dart';
import 'linux_environment_strategy.dart';

class NativeLinuxStrategy extends LinuxEnvironmentStrategy {
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
    final direct = io.File(p.join(emulatorsRoot, executableName));
    if (await direct.exists()) return direct.path;
    return null;
  }

  @override
  Future<void> launch(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
    await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.detached);
  }

  @override
  Future<io.Process?> launchWithHandle(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
    return await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.normal);
  }

  @override
  Future<void> launchStandalone(String emulatorId, String exePath, {List<String> args = const []}) async {
    final exeDir = io.File(exePath).parent.path;
    await io.Process.start(exePath, args, mode: io.ProcessStartMode.detached, workingDirectory: exeDir);
  }
}
