import 'dart:io' as io;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class DolphinStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  DolphinStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  List<String> get launchArgs => io.Platform.isLinux ? <String>[] : ['-b', '-e'];

  @override
  String get name => 'Dolphin';

  @override
  String get emulatorId => 'dolphin';

  @override
  List<String> get supportedSlugs => ['gc', 'gamecube', 'wii', 'ngc'];

  @override
  String get windowsExecutable => 'Dolphin.exe';

  @override
  String get linuxExecutable => 'Dolphin.AppImage';

  @override
  String get macosExecutable => 'Dolphin.app/Contents/MacOS/Dolphin';

  @override
  bool get supportsSaveSync => true;

  @override
  String resolveSavePath(Game game) {
    return ''; // Placeholder
  }
}
