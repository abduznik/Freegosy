import 'dart:io' as io;
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import '../emulator_strategy.dart';

class EdenStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  EdenStrategy(this._directoryService);

  @override
  String get name => 'Eden';

  @override
  String get emulatorId => 'eden';

  @override
  List<String> get supportedSlugs => ['switch', 'nintendo-switch', 'ns'];

  @override
  String get windowsExecutable => 'eden.exe';

  @override
  String get linuxExecutable => 'eden';

  @override
  String get macosExecutable => 'Eden.app/Contents/MacOS/Eden';

  @override
  bool get supportsSaveSync => false;

  @override
  Future<void> launch(Game game, String romPath) async {
    final resolvedPath = _resolveRomPath(romPath);
    final exePath = await _directoryService.findEmulatorExecutable(emulatorId, getExecutableForPlatform());
    if (exePath == null) return;

    String? workingDir;
    if (io.Platform.isMacOS) {
      workingDir = io.File(exePath).parent.path;
    }

    final args = [resolvedPath];
    await io.Process.start(
      exePath,
      args,
      mode: io.ProcessStartMode.detached,
      workingDirectory: workingDir,
    );
  }

  @override
  Future<io.Process?> launchWithHandle(Game game, String romPath) async {
    final resolvedPath = _resolveRomPath(romPath);
    final exePath = await _directoryService.findEmulatorExecutable(emulatorId, getExecutableForPlatform());
    if (exePath == null) return null;

    String? workingDir;
    if (io.Platform.isMacOS) {
      workingDir = io.File(exePath).parent.path;
    }

    final args = [resolvedPath];
    return await io.Process.start(
      exePath,
      args,
      mode: io.ProcessStartMode.normal,
      workingDirectory: workingDir,
    );
  }

  String _resolveRomPath(String romPath) {
    if (io.FileSystemEntity.isDirectorySync(romPath)) {
      final dir = io.Directory(romPath);
      final files = dir.listSync(recursive: true).whereType<io.File>().where((file) {
        final ext = file.path.toLowerCase();
        return ext.endsWith('.nsp') || ext.endsWith('.xci') || ext.endsWith('.nsz');
      }).toList();

      if (files.isEmpty) {
        throw Exception("No valid Switch ROM (.nsp/.xci/.nsz) found in directory.");
      }

      // Sort by file size descending and pick the largest one
      files.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
      return files.first.path;
    }
    return romPath;
  }

  @override
  Future<void> launchStandalone() async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    final exeDir = io.File(exePath).parent.path;

    if (io.Platform.isMacOS) {
      // Find the .app bundle path
      final parts = exePath.split('/');
      final appIdx = parts.indexWhere((p) => p.endsWith('.app'));
      if (appIdx != -1) {
        final appBundlePath = parts.sublist(0, appIdx + 1).join('/');
        if (await io.Directory(appBundlePath).exists()) {
          await io.Process.run('open', [appBundlePath]);
          return;
        }
      }
    }

    await io.Process.start(
      exePath,
      [],
      mode: io.ProcessStartMode.detached,
      workingDirectory: exeDir,
    );
  }

  @override
  String resolveSavePath(Game game) {
    return "";
  }
}
