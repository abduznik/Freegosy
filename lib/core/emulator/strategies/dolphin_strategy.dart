import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class DolphinStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  DolphinStrategy(this._directoryService, {super.platform});

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  List<String> get launchArgs => platform.isLinux ? <String>[] : ['-b', '-e'];

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

  @override
  Future<void> postInstall(String installDir) async {
    // Dolphin requires a portable.txt file in the SAME directory as the executable to run in portable mode.
    // This ensures saves and settings are stored in the emulator directory.
    final exePath = await _directoryService.findEmulatorExecutable(emulatorId, windowsExecutable);
    final targetDir = exePath != null ? io.File(exePath).parent.path : installDir;
    
    final portableTxt = io.File(p.join(targetDir, 'portable.txt'));
    if (!await portableTxt.exists()) {
      await portableTxt.create();
      debugPrint('[Dolphin] Created portable.txt at $targetDir to enable portable mode.');
    }
  }
}
