import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class EdenStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  EdenStrategy(this._directoryService);

  @override
  String get name => 'Eden (Switch)';

  @override
  String get emulatorId => 'eden';

  @override
  List<String> get supportedSlugs => ['switch', 'nintendo-switch', 'ns'];

  @override
  String get windowsExecutable => 'eden.exe';

  @override
  String get linuxExecutable => 'eden';

  @override
  bool get supportsSaveSync => true;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(emulatorId, getExecutableForPlatform());
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    await Process.run(exePath, [romPath]);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(emulatorId, getExecutableForPlatform());
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    return await Process.start(exePath, [romPath], mode: ProcessStartMode.normal);
  }

  @override
  String resolveSavePath(Game game) {
    return ''; // Placeholder
  }
}
