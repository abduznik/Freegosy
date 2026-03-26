import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class Rpcs3Strategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  Rpcs3Strategy(this._directoryService);

  @override
  String get name => 'RPCS3';

  @override
  String get emulatorId => 'rpcs3';

  @override
  List<String> get supportedSlugs => ['ps3', 'playstation-3', 'playstation3'];

  @override
  String get windowsExecutable => 'rpcs3.exe';

  @override
  String get linuxExecutable => 'rpcs3';

  @override
  bool get supportsSaveSync => false;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    await Process.start(exePath, [romPath], mode: ProcessStartMode.detached);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    return await Process.start(exePath, [romPath], mode: ProcessStartMode.normal);
  }

  @override
  String resolveSavePath(Game game) => '';
}