import 'dart:io' as io;
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import '../emulator_strategy.dart';

class EdenStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  EdenStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'Eden';

  @override
  String get emulatorId => 'eden';

  @override
  List<String> get supportedSlugs => ['switch', 'nintendo-switch', 'ns'];

  @override
  String get windowsExecutable => 'eden.exe';

  @override
  String get linuxExecutable => 'eden';

  @override
  String get macosExecutable => 'Eden.app/Contents/MacOS/Eden';

  @override
  Future<String?> findExecutable() async {
    final defaultExe = await super.findExecutable();
    if (defaultExe != null) return defaultExe;

    // If default 'eden' not found, search for AppImage on Linux
    if (io.Platform.isLinux) {
      final emuDir = await _directoryService.getEmulatorDirectory(emulatorId);
      final dir = io.Directory(emuDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is io.File && 
              entity.path.toLowerCase().contains('eden') && 
              entity.path.toLowerCase().endsWith('.appimage')) {
            return entity.path;
          }
        }
      }
    }
    return null;
  }

  @override
  bool get supportsSaveSync => false;

  @override
  String resolveSavePath(Game game) {
    return "";
  }
}
