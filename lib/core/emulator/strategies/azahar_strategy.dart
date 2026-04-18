import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class AzaharStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  AzaharStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'Azahar';

  @override
  String get emulatorId => 'azahar';

  @override
  List<String> get supportedSlugs => [
    '3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds',
    'new-nintendo-3ds', 'new-nintendo-3ds-xl',
  ];

  @override
  String get windowsExecutable => 'azahar.exe';

  @override
  String get linuxExecutable => 'azahar.AppImage';

  @override
  String get macosExecutable => 'Azahar.app/Contents/MacOS/azahar';

  @override
  bool get supportsSaveSync => true;

  @override
  String resolveSavePath(Game game) => '';
}
