import 'dart:io' as io;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class DuckstationStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  DuckstationStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  List<String> get launchArgs => ['-batch', '-fullname'];

  @override
  String get name => 'DuckStation';

  @override
  String get emulatorId => 'duckstation';

  @override
  List<String> get supportedSlugs => ['ps1', 'playstation', 'psx'];

  @override
  String get windowsExecutable => 'duckstation-qt-x64-ReleaseLTCG.exe';

  @override
  String get linuxExecutable => 'DuckStation.AppImage';

  @override
  String get macosExecutable => 'DuckStation.app/Contents/MacOS/DuckStation';

  @override
  bool get supportsSaveSync => true;

  @override
  String resolveSavePath(Game game) {
    if (io.Platform.isMacOS) {
      final home = io.Platform.environment['HOME'];
      if (home != null) {
        return '$home/Library/Application Support/DuckStation/';
      }
    }
    return '';
  }
}
