import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:freegosy/core/romm/romm_models.dart';

/// Thrown when a ROM path falls outside a Flatpak's default sandbox
/// filesystem access, so launching it would fail (or silently show an
/// empty/broken game list) without any indication of why. See issue #75:
/// "Dolphin games with spaces in filename fail to launch" — the real
/// cause was Flatpak confinement, not argv/quoting, for paths outside the
/// default-accessible directories.
class FlatpakSandboxAccessException implements Exception {
  final String flatpakPackageId;
  final String romPath;

  const FlatpakSandboxAccessException(this.flatpakPackageId, this.romPath);

  @override
  String toString() =>
      'FlatpakSandboxAccessException: "$romPath" is outside the default '
      'Flatpak sandbox for $flatpakPackageId. Run:\n'
      '  flatpak override --user --filesystem=$romPath $flatpakPackageId\n'
      '(or grant access to a parent directory) and try again.';
}

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

  /// Splits an [exePath] into `(executable, leadingArguments)`.
  ///
  /// Multi-word commands like `flatpak run org.libretro.RetroArch` must be
  /// split into separate argv entries before being handed to Process.start —
  /// passing the whole string as the executable name fails with ENOENT.
  /// Plain file paths are returned unchanged so spaces inside them are safe.
  static (String, List<String>) splitCommand(String exePath) {
    if (exePath.startsWith('flatpak ')) {
      final parts = exePath.split(' ');
      return (parts.first, parts.sublist(1));
    }
    return (exePath, const []);
  }

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

  /// Returns true if [romPath] falls outside the directories a Flatpak app
  /// can access by default (`$HOME` and its subdirectories, `/run/media`,
  /// `/media`) — i.e. paths like `/mnt/...` or other custom mount points
  /// that require an explicit `flatpak override --filesystem=...` grant.
  ///
  /// This is a pure, unit-testable check with no process/IO dependency —
  /// it does not itself run `flatpak override` or query the sandbox; it
  /// only reasons about path prefixes. Callers (e.g. [NativeLinuxStrategy]
  /// via [checkFlatpakSandboxAccess]) use it to fail fast with an
  /// actionable message instead of a cryptic ProcessException or a game
  /// that silently won't launch.
  static bool isOutsideFlatpakDefaultAccess(String romPath, {required String home}) {
    // Flatpak/Linux paths are always POSIX-style regardless of the
    // development/CI host OS this analysis code happens to run on, so use
    // the posix path context explicitly rather than package:path's
    // platform-default context (which would use Windows semantics if this
    // were ever exercised on a Windows dev machine).
    final posix = p.posix;
    final normalizedPath = posix.normalize(posix.absolute(romPath));
    final normalizedHome = posix.normalize(posix.absolute(home));

    const defaultAccessibleRoots = <String>[
      '/run/media',
      '/media',
    ];

    bool isWithin(String root) {
      final normalizedRoot = posix.normalize(root);
      return normalizedPath == normalizedRoot ||
          posix.isWithin(normalizedRoot, normalizedPath);
    }

    if (normalizedHome.isNotEmpty && (normalizedPath == normalizedHome || isWithin(normalizedHome))) {
      return false;
    }
    for (final root in defaultAccessibleRoots) {
      if (isWithin(root)) return false;
    }
    return true;
  }

  /// Pre-launch check for [romPath] against [flatpakPackageId]'s default
  /// sandbox access. Throws [FlatpakSandboxAccessException] (which the UI
  /// layer's existing error handling already catches and displays) if the
  /// path would be inaccessible to the Flatpak, rather than letting the
  /// launch fail with a cryptic error later. No-op (returns normally) when
  /// access looks fine, so it's safe to call unconditionally before any
  /// Flatpak-based launch.
  static void checkFlatpakSandboxAccess(String flatpakPackageId, String romPath, {required String home}) {
    if (isOutsideFlatpakDefaultAccess(romPath, home: home)) {
      throw FlatpakSandboxAccessException(flatpakPackageId, romPath);
    }
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
