import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class XemuStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  XemuStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  List<String> get launchArgs => ['-dvd_path'];

  @override
  String get name => 'Xemu';

  @override
  String get emulatorId => 'xemu';

  @override
  List<String> get supportedSlugs => ['xbox'];

  @override
  String get windowsExecutable => 'xemu.exe';

  @override
  String get linuxExecutable => 'xemu.AppImage';

  @override
  bool get supportsSaveSync => false;

  @override
  String resolveSavePath(Game game) => '';
}