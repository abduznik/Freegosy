import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class MAMEStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  MAMEStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'MAME';

  @override
  String get emulatorId => 'mame';

  @override
  List<String> get supportedSlugs => ['arcade', 'mame'];

  @override
  String get windowsExecutable => 'mame.exe';

  @override
  String get linuxExecutable => 'mame';

  @override
  bool get supportsSaveSync => false;

  @override
  String resolveSavePath(Game game) => '';
}
