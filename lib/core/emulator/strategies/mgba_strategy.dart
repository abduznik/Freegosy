import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class MGBAStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  MGBAStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'mGBA';

  @override
  String get emulatorId => 'mgba';

  @override
  List<String> get supportedSlugs => ['gba', 'gbc', 'gb', 'game-boy-advance', 'game-boy-color', 'game-boy'];

  @override
  String get windowsExecutable => 'mGBA.exe';

  @override
  String get linuxExecutable => 'mgba';

  @override
  String get macosExecutable => 'mGBA.app/Contents/MacOS/mGBA';

  @override
  bool get supportsSaveSync => false;

  @override
  String resolveSavePath(Game game) => '';
}
