import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class XeniaStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  XeniaStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'Xenia Canary';

  @override
  String get emulatorId => 'xenia_canary';

  @override
  List<String> get supportedSlugs => ['xbox360', 'xbla'];

  @override
  String get windowsExecutable => 'xenia_canary.exe';

  @override
  String get linuxExecutable => 'xenia_canary';

  @override
  bool get supportsSaveSync => false;

  @override
  String resolveSavePath(Game game) => '';
}