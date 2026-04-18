import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class Rpcs3Strategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  Rpcs3Strategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'RPCS3';

  @override
  String get emulatorId => 'rpcs3';

  @override
  List<String> get supportedSlugs => ['ps3', 'playstation-3', 'playstation3'];

  @override
  String get windowsExecutable => 'rpcs3.exe';

  @override
  String get linuxExecutable => 'rpcs3.AppImage';

  @override
  String get macosExecutable => 'RPCS3.app/Contents/MacOS/RPCS3';

  @override
  bool get supportsSaveSync => true;

  @override
  String resolveSavePath(Game game) => '';
}
