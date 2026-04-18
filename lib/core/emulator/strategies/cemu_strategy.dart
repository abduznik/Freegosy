import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class CemuStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  CemuStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  List<String> get launchArgs => ['-g'];

  @override
  String get name => 'Cemu';

  @override
  String get emulatorId => 'cemu';

  @override
  List<String> get supportedSlugs => ['wiiu', 'wii-u', 'nintendo-wii-u', 'nintendo-wiiu'];

  @override
  String get windowsExecutable => 'Cemu.exe';

  @override
  String get linuxExecutable => 'Cemu.AppImage';

  @override
  String get macosExecutable => 'Cemu.app/Contents/MacOS/Cemu';

  @override
  bool get supportsSaveSync => true;

  @override
  String resolveSavePath(Game game) => '';
}
