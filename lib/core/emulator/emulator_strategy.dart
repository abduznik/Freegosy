import 'dart:io';
import 'dart:io' as io;
import 'package:freegosy/core/romm/romm_models.dart';

abstract class EmulatorStrategy {
  String get name;
  String get emulatorId;
  List<String> get supportedSlugs;
  String get windowsExecutable;
  String get linuxExecutable;
  bool get supportsSaveSync;

  String getExecutableForPlatform() {
    if (io.Platform.isWindows) return windowsExecutable;
    if (io.Platform.isLinux) return linuxExecutable;
    return windowsExecutable;
  }

  Future<void> launch(Game game, String romPath);
  Future<Process?> launchWithHandle(Game game, String romPath) async => null;
  String resolveSavePath(Game game);
}
