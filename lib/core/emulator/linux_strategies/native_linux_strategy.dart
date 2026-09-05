import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'linux_environment_strategy.dart';

class NativeLinuxStrategy extends LinuxEnvironmentStrategy {
  // Cache for Flatpak detection — avoids running `flatpak list` repeatedly.
  Map<String, String>? _flatpakCache;
  final PlatformInfo _platform;

  NativeLinuxStrategy({PlatformInfo? platform}) : _platform = platform ?? PlatformInfo.current;

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
    // check common configuration directory for flatpak instalations
    var lowerCaseEmulatorName = emulatorName.toLowerCase();
    var flatpakPackage = kEmulatorFlatpakPackages[lowerCaseEmulatorName];
    if(flatpakPackage != null) {
      var supportDirectoryParent = p.join(home, ".var", "app", flatpakPackage, "config");
      final dir = io.Directory(supportDirectoryParent);
      if(dir.existsSync()) {
          var lowerAppName = flatpakPackage.split('.').last.toLowerCase();
          for (final entity in dir.listSync()) {  
            if (entity is io.File) continue;
            final lowerFolderName = p.basename(entity.path).toLowerCase();
            if (lowerFolderName == lowerAppName) {
              return entity.path;
            }
          }
      }
    }
    // check common configuration directory for app image instalations
    var altSupportDirectoryPath =  p.join(home, '.local', 'share', lowerCaseEmulatorName);
    if(io.Directory(altSupportDirectoryPath).existsSync()) {
          return altSupportDirectoryPath;
    }
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

    // 2. Check common AppImage locations (EmuDeck, Gear Lever, manual installs)
    final home = _platform.environment['HOME'] ?? '';
    final searchDirs = [
      io.Directory(p.join(home, 'Applications')),
      io.Directory(p.join(home, 'AppImages')),
      io.Directory(p.join(home, '.local', 'bin')),
      io.Directory(p.join(home, 'bin')),
    ];
    for (final dir in searchDirs) {
      if (!await dir.exists()) continue;

      // Exact name match
      final candidate = io.File(p.join(dir.path, executableName));
      if (await candidate.exists()) return candidate.path;

      // Case-insensitive fallback for AppImage files and other executables
      try {
        final entries = await dir.list().toList();
        for (final entry in entries) {
          if (entry is! io.File) continue;
          final baseName = p.basename(entry.path);
          final baseNameLower = baseName.toLowerCase();
          final targetLower = executableName.toLowerCase();

          // Exact match (case-insensitive)
          if (baseNameLower == targetLower) return entry.path;

          // Match AppImage files: e.g. "PCSX2.AppImage" matches "pcsx2"
          if (baseNameLower.endsWith('.appimage') &&
              baseNameLower == '$targetLower.appimage') {
            return entry.path;
          }

          // Fuzzy match: strip common suffixes and compare
          final stripped = baseNameLower
              .replaceAll(RegExp(r'[-_]?(x86_64|amd64|linux|gtk).*'), '')
              .replaceAll(RegExp(r'\.(appimage|AppImage)$'), '');
          if (stripped == targetLower) return entry.path;
        }
      } catch (_) {
        // Silently ignore permission errors or other listing issues
      }
    }

    // 3. Check if a Flatpak is installed for this emulator
    final flatpakPkg = await _flatpakPackageFor(emulatorId);
    if (flatpakPkg != null) {
      // Return the Flatpak command string — the launch method will handle it
      return 'flatpak run $flatpakPkg';
    }

    return null;
  }

  @override
  Future<void> launch(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
    final (exe, cmdArgs) = LinuxEnvironmentStrategy.splitCommand(exePath);
    _checkFlatpakSandboxAccessIfNeeded(exe, cmdArgs, romPath);
    if (cmdArgs.isNotEmpty) {
      // Flatpak commands (e.g. "flatpak run org.DolphinEmu.dolphin-emu") are
      // resolved via a raw PATH lookup by Process.start, which uses the app's
      // inherited environment rather than a shell-resolved one. On some
      // desktop/session setups (e.g. Steam Deck gamescope sessions) that PATH
      // doesn't include `flatpak`, causing a ProcessException even though
      // `flatpak` works fine from an interactive shell. Force shell resolution
      // for this case specifically — see issue #84.
      await io.Process.start(exe, [...cmdArgs, ...args, romPath], mode: io.ProcessStartMode.detached, runInShell: exe == 'flatpak');
    } else if (exePath.endsWith('.sh')) {
      await io.Process.start('bash', [exePath, ...args, romPath], mode: io.ProcessStartMode.detached);
    } else {
      await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.detached);
    }
  }

  @override
  Future<io.Process?> launchWithHandle(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
    final (exe, cmdArgs) = LinuxEnvironmentStrategy.splitCommand(exePath);
    _checkFlatpakSandboxAccessIfNeeded(exe, cmdArgs, romPath);
    if (cmdArgs.isNotEmpty) {
      // See comment in launch() above regarding runInShell for flatpak commands.
      return await io.Process.start(exe, [...cmdArgs, ...args, romPath], mode: io.ProcessStartMode.normal, runInShell: exe == 'flatpak');
    } else if (exePath.endsWith('.sh')) {
      return await io.Process.start('bash', [exePath, ...args, romPath], mode: io.ProcessStartMode.normal);
    } else {
      return await io.Process.start(exePath, [...args, romPath], mode: io.ProcessStartMode.normal);
    }
  }

  @override
  Future<void> launchStandalone(String emulatorId, String exePath, {List<String> args = const []}) async {
    final (exe, cmdArgs) = LinuxEnvironmentStrategy.splitCommand(exePath);
    if (cmdArgs.isNotEmpty) {
      // See comment in launch() above regarding runInShell for flatpak commands.
      await io.Process.start(exe, [...cmdArgs, ...args], mode: io.ProcessStartMode.detached, runInShell: exe == 'flatpak');
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

  /// Additive pre-launch check (issue #75): if [exe]/[cmdArgs] represent a
  /// `flatpak run <package-id>` invocation, verify [romPath] is within the
  /// Flatpak's default sandbox access before handing off to Process.start.
  /// Flatpak confines its filesystem access to `$HOME`, `/run/media`, and
  /// `/media` by default — a ROM stored elsewhere (e.g. `/mnt/qvo/...`)
  /// fails to launch regardless of filename, which was previously
  /// misdiagnosed as a "spaces in filename" bug. Throws
  /// [FlatpakSandboxAccessException] with an actionable
  /// `flatpak override --user --filesystem=...` command; does nothing for
  /// non-Flatpak launches or paths already inside the default allowlist.
  void _checkFlatpakSandboxAccessIfNeeded(String exe, List<String> cmdArgs, String romPath) {
    if (exe != 'flatpak' || cmdArgs.length < 2 || cmdArgs.first != 'run') return;
    final flatpakPackageId = cmdArgs[1];
    final home = _platform.environment['HOME'] ?? '';
    if (home.isEmpty) return; // Can't determine default access without $HOME; skip rather than false-positive.
    LinuxEnvironmentStrategy.checkFlatpakSandboxAccess(flatpakPackageId, romPath, home: home);
  }
}
