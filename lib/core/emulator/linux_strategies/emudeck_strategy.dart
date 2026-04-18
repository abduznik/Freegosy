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
      // EmuDeck folder names mapping (some are capitalized)
      final Map<String, String> emudeckSavesMap = {
        'cemu': 'Cemu',
        'vita3k': 'Vita3K',
        'mame': 'MAME',
        'pcsx2': 'pcsx2',
        'retroarch': 'retroarch',
      };

      final emuFolderName = emudeckSavesMap[emulatorName.toLowerCase()] ?? emulatorName.toLowerCase();
      
      // EmuDeck usually has a subfolder named 'saves' inside the emulator folder in Emulation/saves/
      // e.g., Emulation/saves/retroarch/saves
      String base = p.join(emudeckRoot, 'Emulation', 'saves', emuFolderName);
      
      // Check if there is a 'saves' subfolder, if so use it as base
      if (io.Directory(p.join(base, 'saves')).existsSync()) {
        base = p.join(base, 'saves');
      }

      if (emulatorName.toLowerCase() == 'dolphin' || emulatorName.toLowerCase() == 'primehack') {
        if (platformSlug != null) {
          final slug = platformSlug.toLowerCase();
          if (slug == 'gc' || slug == 'gamecube' || slug == 'ngc') return p.join(base, 'GC');
          if (slug == 'wii') return p.join(base, 'Wii');
        }
        // Handle StateSaves if requested (this might be called specifically or we just return base)
        if (io.Directory(p.join(base, 'StateSaves')).existsSync()) {
          // If we are looking for states, we might need to return this, but Strategy handles subfolders
        }
      }

      if (emulatorName.toLowerCase() == 'pcsx2') {
        // PCSX2 saves are in /pcsx2/saves
        if (io.Directory(p.join(base, 'saves')).existsSync()) {
           // If we already appended saves, and there is another one? 
           // Log says .../saves/pcsx2/saves
        }
        return base;
      }

      return platformSlug != null ? p.join(base, platformSlug) : base;
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
    if (isEmuLaunchScript(exePath)) {
      // Convert internal emulator ID to EmuDeck expected key if necessary
      final emuKeyMap = {
        'pcsx2': 'pcsx2-Qt',
        'retroarch': 'retroarch',
        'xemu': 'xemu-emu',
        'dolphin': 'dolphin-emu',
        'citra': 'citra-qt',
        'azahar': 'azahar',
        'eden': 'eden',
        'ryujinx': 'ryujinx',
      };
      final emuKey = emuKeyMap[emulatorId] ?? emulatorId;
      await io.Process.start('bash', [exePath, '-e', emuKey, ...args, romPath], mode: io.ProcessStartMode.detached);
    } else if (exePath.endsWith('.sh')) {
      await io.Process.start('bash', [exePath, ...args, romPath], mode: io.ProcessStartMode.detached);
    } else {
      await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.detached);
    }
  }

  @override
  Future<io.Process?> launchWithHandle(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
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
      };
      final emuKey = emuKeyMap[emulatorId] ?? emulatorId;
      return await io.Process.start('bash', [exePath, '-e', emuKey, ...args, romPath], mode: io.ProcessStartMode.normal);
    } else if (exePath.endsWith('.sh')) {
      return await io.Process.start('bash', [exePath, ...args, romPath], mode: io.ProcessStartMode.normal);
    } else {
      return await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.normal);
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
}
