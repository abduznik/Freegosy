import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/retroachievements/retroachievements_emulator_login.dart';
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

  /// Whether this emulator's save states can be synced through RomM's states
  /// API. Only true where the matching save strategy implements
  /// `StateSyncCapable` (a unit test enforces that they agree).
  bool get supportsStateSync => false;

  /// Whether this emulator can boot straight into a save state given on its
  /// command line (see [stateLoadArgs]). Only true where the matching save
  /// strategy is `StateSyncCapable` (a unit test enforces that they agree).
  ///
  /// `GameLaunchService.launch` passes the state arguments to
  /// [launchWithExtraArgs] / [launchWithHandleAndExtraArgs] for that launch
  /// only, so an emulator that supports this must not override [launch] or
  /// [launchWithHandle] in a way that skips the base implementation; override
  /// the `...ExtraArgs` variants instead. Nothing per-launch is stored on the
  /// strategy: it is one shared instance and launches can overlap.
  bool get supportsStateLoadOnLaunch => false;

  /// Command-line arguments that make the emulator load the state at
  /// [statePath]. Only used when [supportsStateLoadOnLaunch] is true.
  List<String> stateLoadArgs(String statePath) => const [];

  /// Whether the state file named [fileName] can be loaded with
  /// [stateLoadArgs]. A state this says no to is not offered by Resume Game
  /// (RetroArch's command line can load numbered slots but not its auto slot).
  bool canLoadState(String fileName) => true;

  /// The installed emulator's version as the emulator reports it (e.g.
  /// `2.8.2.0`), or null when it cannot be determined. Compared with the
  /// version a save state records to warn before loading a state from a
  /// different build. Must never throw.
  Future<String?> installedVersion() async => null;

  /// A human-readable account of what launching [game] from [romPath] would run (the command line and the
  /// environment that matters), without starting anything; null when this strategy can't say. Backs the
  /// headless `launch --dry-run`.
  Future<String?> describeLaunch(Game game, String romPath) async => null;

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

  Future<void> launch(Game game, String romPath) => launchWithExtraArgs(game, romPath);

  Future<Process?> launchWithHandle(Game game, String romPath) =>
      launchWithHandleAndExtraArgs(game, romPath);

  /// [launch] with [extraArgs] (e.g. [stateLoadArgs]) appended to [launchArgs]
  /// for this launch only. Subclasses that support loading a state on launch
  /// override this rather than [launch] (see [supportsStateLoadOnLaunch]).
  Future<void> launchWithExtraArgs(Game game, String romPath,
      {List<String> extraArgs = const []}) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    final normalizedRomPath = p.absolute(p.normalize(romPath));
    await preLaunch(game, romPath);
    await directoryService.launchGame(game, normalizedRomPath, emulatorId, exePath, args: [...launchArgs, ...extraArgs]);
    await postLaunch(game, romPath);
  }

  /// [launchWithHandle] with [extraArgs] (e.g. [stateLoadArgs]) appended to
  /// [launchArgs] for this launch only. Subclasses that support loading a
  /// state on launch override this rather than [launchWithHandle] (see
  /// [supportsStateLoadOnLaunch]).
  Future<Process?> launchWithHandleAndExtraArgs(Game game, String romPath,
      {List<String> extraArgs = const []}) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    final normalizedRomPath = p.absolute(p.normalize(romPath));
    await preLaunch(game, romPath);
    final process = await directoryService.launchGameWithHandle(game, normalizedRomPath, emulatorId, exePath, args: [...launchArgs, ...extraArgs]);
    await process?.exitCode;
    await postLaunch(game, romPath);
    return process;
  }

  /// Whether this strategy signs the emulator in to RetroAchievements using
  /// the login saved in Settings (see `RetroAchievementsEmulatorLogin`).
  ///
  /// How it signs in is the emulator's own: RetroArch takes an `--appendconfig`
  /// file on its command line; PCSX2 has no such option, so
  /// [applyRetroAchievementsLogin] writes the login into its config files
  /// before launch. Either way it must never fail a launch if it can't.
  ///
  /// Planned, each storing the same RA token in its own config:
  /// DuckStation (settings.ini `[Cheevos]`; its token is encrypted with a
  /// machine-specific key), PPSSPP (`[Achievements]` + token secret) and
  /// Dolphin (RetroAchievements.ini).
  bool get supportsRetroAchievementsLogin => false;

  /// Writes [login] into the emulator's own config so it is signed in to
  /// RetroAchievements at its next start. Called before launch by emulators
  /// that sign in through their config files (see
  /// [supportsRetroAchievementsLogin]). Must never throw, and does nothing
  /// when the emulator has not been run yet (no config to edit).
  Future<void> applyRetroAchievementsLogin(RetroAchievementsEmulatorLogin login) async {}

  /// Removes what [applyRetroAchievementsLogin] wrote (the token above all),
  /// when the user disconnects their account in Settings. Only a login for
  /// [username] is removed: one the user set up in the emulator themselves
  /// stays. Must never throw.
  Future<void> clearRetroAchievementsLogin(String username) async {}

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
