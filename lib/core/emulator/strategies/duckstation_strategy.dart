import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:path/path.dart' as p;

class DuckstationStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  DuckstationStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  List<String> get launchArgs => ['-batch', '-fullscreen'];

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

  @override
  Future<void> postInstall(String installDir) async {
    if (io.Platform.isWindows) {
      // DuckStation requires a portable.txt file in the SAME directory as the executable to run in portable mode.
      final exePath = await _directoryService.findEmulatorExecutable(emulatorId, windowsExecutable);
      final targetDir = exePath != null ? io.File(exePath).parent.path : installDir;
      
      final portableTxt = io.File(p.join(targetDir, 'portable.txt'));
      if (!await portableTxt.exists()) {
        await portableTxt.create();
        debugPrint('[DuckStation] Created portable.txt at $targetDir to enable portable mode.');
      }
    }
  }
}
