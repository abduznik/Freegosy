import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/emulator/linux_strategies/linux_environment_strategy.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/scummvm_save_strategy.dart';
import 'package:freegosy/core/storage/directory_service.dart';

/// ScummVM. A ScummVM game is a folder of data files, not a ROM:
/// ScummVM is started with `--auto-detect --path=<game folder>`, which
/// detects the game in that folder and starts it. ScummVM rejects a folder
/// passed as a plain argument ("Unrecognized game"), so unlike other
/// emulators the ROM path isn't appended to the command line and this
/// strategy starts the process itself.
class ScummVMStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  ScummVMStrategy(this._directoryService, {super.platform});

  /// RomM platform slugs whose games are started with ScummVM.
  static const slugs = ['scummvm'];

  /// Where distributions install ScummVM on Linux, checked after the usual
  /// emulator locations and Flatpak.
  static const linuxSystemLocations = ['/usr/bin/scummvm', '/usr/games/scummvm', '/usr/local/bin/scummvm'];

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'ScummVM';

  @override
  String get emulatorId => 'scummvm';

  @override
  List<String> get supportedSlugs => slugs;

  @override
  String get windowsExecutable => 'scummvm.exe';

  @override
  String get linuxExecutable => 'scummvm';

  @override
  String get macosExecutable => 'ScummVM.app/Contents/MacOS/scummvm';

  @override
  bool get supportsSaveSync => true;

  @override
  String resolveSavePath(Game game) => '';

  /// The folder holding the game: [romPath] itself, or the folder of the
  /// file that was picked inside it.
  static String gameFolderFor(String romPath) =>
      io.Directory(romPath).existsSync() ? romPath : p.dirname(romPath);

  /// Arguments that make ScummVM detect and start the game in [gameFolder].
  /// With [savePath], ScummVM saves there instead of its shared save folder, which
  /// is what lets one game's saves sync on their own (see [ScummVMSaveStrategy]).
  static List<String> gameArgs(String gameFolder, {String? savePath}) =>
      ['--auto-detect', '--path=$gameFolder', if (savePath != null) '--savepath=$savePath'];

  @override
  Future<String?> findExecutable() async {
    final found = await super.findExecutable();
    if (found != null || !platform.isLinux) return found;
    for (final path in linuxSystemLocations) {
      if (await io.File(path).exists()) return path;
    }
    return null;
  }

  @override
  Future<void> launchWithExtraArgs(Game game, String romPath, {List<String> extraArgs = const []}) async {
    await _start(game, romPath, extraArgs, io.ProcessStartMode.detached);
  }

  @override
  Future<io.Process?> launchWithHandleAndExtraArgs(Game game, String romPath, {List<String> extraArgs = const []}) async {
    final process = await _start(game, romPath, extraArgs, io.ProcessStartMode.normal);
    // Pipes must be drained or ScummVM blocks once they fill up (see
    // DirectoryService.launchGameWithHandle).
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    await process.exitCode;
    return process;
  }

  @override
  Future<String?> describeLaunch(Game game, String romPath) async {
    final exePath = await findExecutable();
    if (exePath == null) return '$name is not installed.';
    final folder = gameFolderFor(p.absolute(p.normalize(romPath)));
    final savePath = await ScummVMSaveStrategy.saveDirFor(_directoryService, game);
    final (exe, args) = commandFor(exePath, [...launchArgs, ...gameArgs(folder, savePath: savePath)], platform: platform);
    return 'Command: ${[exe, ...args].join(' ')}\nSaves: $savePath';
  }

  Future<io.Process> _start(Game game, String romPath, List<String> extraArgs, io.ProcessStartMode mode) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    final folder = gameFolderFor(p.absolute(p.normalize(romPath)));
    final savePath = await ScummVMSaveStrategy.saveDirFor(_directoryService, game);
    await io.Directory(savePath).create(recursive: true);
    final (exe, args) = commandFor(exePath, [...launchArgs, ...extraArgs, ...gameArgs(folder, savePath: savePath)], platform: platform);
    final workingDirectory = p.isAbsolute(exe) && !LinuxEnvironmentStrategy.isFlatpakExecutable(exe) ? p.dirname(exe) : null;
    return io.Process.start(exe, args, mode: mode, workingDirectory: workingDirectory, runInShell: exe == 'flatpak');
  }

  /// The executable and arguments that run [exePath] with [args]: a
  /// `flatpak run …` command is split up, and an EmuDeck-style `.sh`
  /// launcher is run through bash.
  static (String, List<String>) commandFor(String exePath, List<String> args, {required PlatformInfo platform}) {
    if (platform.isLinux) {
      final (exe, cmdArgs) = LinuxEnvironmentStrategy.splitCommand(exePath);
      if (cmdArgs.isNotEmpty) return (exe, [...cmdArgs, ...args]);
      if (exePath.endsWith('.sh')) return ('bash', [exePath, ...args]);
    }
    return (exePath, args);
  }
}
