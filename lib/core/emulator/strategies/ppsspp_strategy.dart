import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class PPSSPPStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  PPSSPPStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'PPSSPP';

  @override
  String get emulatorId => 'ppsspp';

  @override
  List<String> get supportedSlugs => ['psp', 'playstation-portable'];

  @override
  String get windowsExecutable => 'PPSSPPWindows64.exe';

  @override
  String get linuxExecutable => 'PPSSPP';

  @override
  String get macosExecutable => 'PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL';

  @override
  bool get supportsSaveSync => true;

  @override
  String resolveSavePath(Game game) => '';
}
