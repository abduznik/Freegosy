import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
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

  /// The installed emulator's version as the emulator reports it (e.g.
  /// `2.8.2.0`), or null when it cannot be determined. Compared with the
  /// version a save state records to warn before loading a state from a
  /// different build. Must never throw.
  Future<String?> installedVersion() async => null;

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

  /// Whether this strategy signs the emulator in to RetroAchievements at
  /// launch using the login saved in Settings (see
  /// `RetroAchievementsEmulatorLogin`). Only RetroArch does so far.
  ///
  /// Planned, each storing the same RA token in its own config:
  /// DuckStation (settings.ini `[Cheevos]`), PCSX2 (PCSX2.ini `[Achievements]`),
  /// PPSSPP (`[Achievements]` + token file), Dolphin (RetroAchievements.ini).
  /// An implementation overrides this to true and applies the login from
  /// its launch path, never failing the launch if it can't.
  bool get supportsRetroAchievementsLogin => false;

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
