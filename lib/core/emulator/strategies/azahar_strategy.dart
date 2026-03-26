import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class AzaharStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  AzaharStrategy(this._directoryService);

  @override
  String get name => 'Azahar';

  @override
  String get emulatorId => 'azahar';

  @override
  List<String> get supportedSlugs => [
    '3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds',
    'new-nintendo-3ds', 'new-nintendo-3ds-xl',
  ];

  @override
  String get windowsExecutable => 'azahar.exe';

  @override
  String get linuxExecutable => 'azahar';

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