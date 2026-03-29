import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class MelonDSStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  MelonDSStrategy(this._directoryService);

  @override
  String get name => 'melonDS';

  @override
  String get emulatorId => 'melonds';

  @override
  List<String> get supportedSlugs => ['nds', 'nintendo-ds', 'ds'];

  @override
  String get windowsExecutable => 'melonDS.exe';

  @override
  String get linuxExecutable => 'melonDS';

  @override
  bool get supportsSaveSync => false;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(emulatorId, getExecutableForPlatform());
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    final workingDir = File(exePath).parent.path;
    await Process.start(exePath, [romPath], workingDirectory: workingDir, mode: ProcessStartMode.detached);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(emulatorId, getExecutableForPlatform());
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    final workingDir = File(exePath).parent.path;
    final process = await Process.start(exePath, [romPath], workingDirectory: workingDir, mode: ProcessStartMode.normal);
    process.stdout.drain();
    process.stderr.drain();
    return process;
  }

  @override
  Future<void> launchStandalone() async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    final workingDir = File(exePath).parent.path;
    await Process.start(exePath, [], workingDirectory: workingDir, mode: ProcessStartMode.detached);
  }

  @override
  String resolveSavePath(Game game) {
    return ''; // Placeholder
  }
}
