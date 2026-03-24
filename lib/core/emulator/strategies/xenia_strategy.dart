import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class XeniaStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  XeniaStrategy(this._directoryService);

  @override
  String get name => 'Xenia Canary';

  @override
  String get emulatorId => 'xenia_canary';

  @override
  List<String> get supportedSlugs => ['xbox360', 'xbla'];

  @override
  String get windowsExecutable => 'xenia_canary.exe';

  @override
  String get linuxExecutable => 'xenia_canary';

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
  String resolveSavePath(Game game) => '';
}