import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:freegosy/core/romm/romm_models.dart';
import 'linux_environment_strategy.dart';

class EmuDeckStrategy extends LinuxEnvironmentStrategy {
  @override
  String get name => 'EmuDeck';

  @override
  String get id => 'emudeck';

  @override
  String getRomsRoot(String home, String? customPath, String? emudeckRoot) {
    if (emudeckRoot != null) {
      return customPath ?? p.join(emudeckRoot, 'Emulation/roms');
    }
    return customPath ?? p.join(home, 'ROMs');
  }

  @override
  String getEmulatorsRoot(String home, String? customPath, String? emudeckRoot) {
    if (emudeckRoot != null) {
      return customPath ?? p.join(emudeckRoot, 'Emulation/tools');
    }
    return customPath ?? p.join(home, 'Emulators');
  }

  @override
  String getEmulatorAppSupportDirectory(String home, String emulatorName, String? emudeckRoot, {String? platformSlug}) {
    if (emudeckRoot != null) {
      // EmuDeck folder names mapping based on your exact ls -la output
      final Map<String, String> emudeckFolderMap = {
        'cemu': 'Cemu',
        'vita3k': 'Vita3K',
        'mame': 'MAME',
        'pcsx2': 'pcsx2',
        'ppsspp': 'ppsspp',
        'retroarch': 'retroarch',
        'rpcs3': 'rpcs3',
        'ryujinx': 'ryujinx',
        'yuzu': 'yuzu',
        'azahar': 'azahar',
        'citra': 'citra',
        'xenia': 'xenia',
        'shadps4': 'shadps4',
      };

      final folderName = emudeckFolderMap[emulatorName.toLowerCase()] ?? emulatorName;
      final emuSavesBase = p.join(emudeckRoot, 'Emulation', 'saves', folderName);

      // PREFERENCE 1: The 'saves' symlink (definitive target on Steam Deck)
      final symlinkSaves = p.join(emuSavesBase, 'saves');
      if (io.Directory(symlinkSaves).existsSync() || io.Link(symlinkSaves).existsSync()) {
        return symlinkSaves;
      }

      // PREFERENCE 2: Platform-specific legacy logic if no 'saves' link exists
      if (emulatorName.toLowerCase() == 'rpcs3') {
        return p.join(emuSavesBase, 'dev_hdd0', 'home', '00000001', 'savedata');
      }
      if (emulatorName.toLowerCase() == 'ryujinx' || emulatorName.toLowerCase() == 'eden') {
        return p.join(emuSavesBase, 'bis', 'user', 'save');
      }
      if (emulatorName.toLowerCase() == 'cemu') {
        return p.join(emuSavesBase, 'Cemu', 'mlc01', 'usr', 'save');
      }

      return emuSavesBase;
    }
    return p.join(home, '.config', emulatorName);
  }

  @override
  String getBiosPath(String home, String? emudeckRoot) {
    if (emudeckRoot != null) {
      return p.join(emudeckRoot, 'Emulation', 'bios');
    }
    return p.join(home, 'Emulators', 'BIOS');
  }

  @override
  Future<String?> findExecutable(String emulatorId, String executableName, String emulatorsRoot, String? emudeckRoot) async {
    if (emudeckRoot != null) {
      final masterLauncher = io.File(p.join(emudeckRoot, 'Emulation', 'tools', 'emu-launch.sh'));
      if (await masterLauncher.exists()) {
        return masterLauncher.path;
      }

      final Map<String, String> emudeckMap = {
        'rpcs3': 'rpcs3.sh',
        'pcsx2': 'pcsx2-qt.sh',
        'dolphin': 'dolphin-emu.sh',
        'xemu': 'xemu-emu.sh',
        'xenia_canary': 'xenia.sh',
        'citra': 'citra.sh',
        'azahar': 'azahar.sh',
        'duckstation': 'duckstation.sh',
        'melonds': 'melonds.sh',
        'mgba': 'mgba.sh',
        'ppsspp': 'ppsspp.sh',
        'retroarch': 'retroarch.sh',
        'mame': 'mame.sh',
        'cemu': 'cemu.sh',
        'flycast': 'flycast.sh',
        'vita3k': 'vita3k.sh',
        'ryujinx': 'ryujinx.sh',
      };

      final launcherName = emudeckMap[emulatorId] ?? '$emulatorId.sh';
      final launcherFile = io.File(p.join(emudeckRoot, 'Emulation', 'tools', 'launchers', launcherName));
      if (await launcherFile.exists()) {
        return launcherFile.path;
      }
    }
    return null;
  }

  bool isEmuLaunchScript(String path) => p.basename(path) == 'emu-launch.sh';

  @override
  Future<void> launch(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
    final resolvedRomPath = await _resolveWiiURom(romPath, emulatorId);
    final absRomPath = p.absolute(resolvedRomPath);
    
    if (isEmuLaunchScript(exePath)) {
      final emuKeyMap = {
        'pcsx2': 'pcsx2-Qt',
        'retroarch': 'retroarch',
        'xemu': 'xemu-emu',
        'dolphin': 'dolphin-emu',
        'citra': 'citra-qt',
        'azahar': 'azahar',
        'eden': 'eden',
        'ryujinx': 'ryujinx',
        'rpcs3': 'rpcs3',
        'cemu': 'cemu',
      };
      final emuKey = emuKeyMap[emulatorId] ?? emulatorId;
      await io.Process.start('bash', [exePath, '-e', emuKey, ...args, absRomPath], mode: io.ProcessStartMode.detached);
    } else if (exePath.endsWith('.sh')) {
      await io.Process.start('bash', [exePath, ...args, absRomPath], mode: io.ProcessStartMode.detached);
    } else {
      await io.Process.start(exePath, [...args, absRomPath], mode: io.ProcessStartMode.detached);
    }
  }

  @override
  Future<io.Process?> launchWithHandle(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
    final resolvedRomPath = await _resolveWiiURom(romPath, emulatorId);
    final absRomPath = p.absolute(resolvedRomPath);
    
    if (isEmuLaunchScript(exePath)) {
      final emuKeyMap = {
        'pcsx2': 'pcsx2-Qt',
        'retroarch': 'retroarch',
        'xemu': 'xemu-emu',
        'dolphin': 'dolphin-emu',
        'citra': 'citra-qt',
        'azahar': 'azahar',
        'eden': 'eden',
        'ryujinx': 'ryujinx',
        'rpcs3': 'rpcs3',
        'cemu': 'cemu',
      };
      final emuKey = emuKeyMap[emulatorId] ?? emulatorId;
      return await io.Process.start('bash', [exePath, '-e', emuKey, ...args, absRomPath], mode: io.ProcessStartMode.normal);
    } else if (exePath.endsWith('.sh')) {
      return await io.Process.start('bash', [exePath, ...args, absRomPath], mode: io.ProcessStartMode.normal);
    } else {
      return await io.Process.start(exePath, [...args, absRomPath], mode: io.ProcessStartMode.normal);
    }
  }

  @override
  Future<void> launchStandalone(String emulatorId, String exePath, {List<String> args = const []}) async {
    if (isEmuLaunchScript(exePath)) {
      final emuKeyMap = {
        'pcsx2': 'pcsx2-Qt',
        'retroarch': 'retroarch',
        'xemu': 'xemu-emu',
        'dolphin': 'dolphin-emu',
        'citra': 'citra-qt',
        'azahar': 'azahar',
        'eden': 'eden',
        'ryujinx': 'ryujinx',
        'rpcs3': 'rpcs3',
        'cemu': 'cemu',
      };
      final emuKey = emuKeyMap[emulatorId] ?? emulatorId;
      await io.Process.start('bash', [exePath, '-e', emuKey, ...args], mode: io.ProcessStartMode.detached);
    } else if (exePath.endsWith('.sh')) {
      await io.Process.start('bash', [exePath, ...args], mode: io.ProcessStartMode.detached);
    } else {
      final exeDir = io.File(exePath).parent.path;
      await io.Process.start(exePath, args, mode: io.ProcessStartMode.detached, workingDirectory: exeDir);
    }
  }

  Future<String> _resolveWiiURom(String romPath, String emulatorId) async {
    if (emulatorId.toLowerCase() != 'cemu') return romPath;
    
    final dir = io.Directory(romPath);
    if (!dir.existsSync()) return romPath;

    // Check for common Wii U leaf files in the directory
    final candidates = [
      p.join(romPath, 'code', 'app.rpx'),
      p.join(romPath, 'app.rpx'),
    ];

    for (final c in candidates) {
      if (io.File(c).existsSync()) {
        return c;
      }
    }

    // Look for any .wua file inside if it was a folder download
    try {
      final files = dir.listSync(recursive: true);
      for (final f in files) {
        if (f is io.File && f.path.toLowerCase().endsWith('.wua')) {
          return f.path;
        }
      }
    } catch (_) {}

    return romPath;
  }
}
