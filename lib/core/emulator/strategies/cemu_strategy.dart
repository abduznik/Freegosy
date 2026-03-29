import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class CemuStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  CemuStrategy(this._directoryService);

  @override
  String get name => 'Cemu';

  @override
  String get emulatorId => 'cemu';

  @override
  List<String> get supportedSlugs => ['wiiu', 'wii-u', 'nintendo-wii-u', 'nintendo-wiiu'];

  @override
  String get windowsExecutable => 'Cemu.exe';

  @override
  String get linuxExecutable => 'cemu';

  @override
  bool get supportsSaveSync => false;

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    await Process.start(exePath, ['-g', romPath], mode: ProcessStartMode.detached);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    return await Process.start(exePath, ['-g', romPath], mode: ProcessStartMode.normal);
  }

  @override
  Future<void> launchStandalone() async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    await Process.start(exePath, [], mode: ProcessStartMode.detached);
  }

  @override
  String resolveSavePath(Game game) => '';
}