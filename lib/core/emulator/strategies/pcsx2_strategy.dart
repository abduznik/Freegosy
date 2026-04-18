import 'dart:io' as io;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class Pcsx2Strategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  Pcsx2Strategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  List<String> get launchArgs => ['-batch', '-fullscreen'];

  @override
  String get name => 'PCSX2';

  @override
  String get emulatorId => 'pcsx2';

  @override
  List<String> get supportedSlugs => ['ps2', 'playstation-2', 'playstation2'];

  @override
  String get windowsExecutable => 'pcsx2-qt.exe';

  @override
  String get linuxExecutable => 'pcsx2-qt.AppImage';

  @override
  String get macosExecutable => 'PCSX2.app/Contents/MacOS/PCSX2';

  @override
  bool get supportsSaveSync => true;

  @override
  String resolveSavePath(Game game) {
    if (io.Platform.isMacOS) {
      final home = io.Platform.environment['HOME'];
      if (home != null) {
        return '$home/Library/Application Support/PCSX2/';
      }
    }
    return '';
  }
}
