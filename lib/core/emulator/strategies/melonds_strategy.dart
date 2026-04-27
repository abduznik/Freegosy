import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class MelonDSStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  MelonDSStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'melonDS';

  @override
  String get emulatorId => 'melonds';

  @override
  List<String> get supportedSlugs => ['nds', 'nintendo-ds', 'ds'];

  @override
  String get windowsExecutable => 'melonDS.exe';

  @override
  String get linuxExecutable => 'melonDS';

  @override
  String get macosExecutable => 'melonDS.app/Contents/MacOS/melonDS';

  @override
  bool get supportsSaveSync => true;

  @override
  String resolveSavePath(Game game) {
    return ''; // Placeholder
  }

  @override
  Future<void> preLaunch(Game game, String romPath) async {
    final srmPath = romPath.replaceAll(RegExp(r'\.[^.]+$'), '.srm');
    final savPath = romPath.replaceAll(RegExp(r'\.[^.]+$'), '.sav');
    final srmFile = File(srmPath);
    if (await srmFile.exists()) {
      await srmFile.copy(savPath);
      debugPrint('[MelonDS-Save] Translated SRM to SAV');
    }
  }

  @override
  Future<void> postLaunch(Game game, String romPath) async {
    final srmPath = romPath.replaceAll(RegExp(r'\.[^.]+$'), '.srm');
    final savPath = romPath.replaceAll(RegExp(r'\.[^.]+$'), '.sav');
    final srmFile = File(srmPath);
    final savFile = File(savPath);
    if (await savFile.exists()) {
      if (!(await srmFile.exists()) || (await savFile.lastModified()).isAfter(await srmFile.lastModified())) {
        await savFile.copy(srmPath);
        debugPrint('[MelonDS-Save] Synced SAV back to SRM');
      }
    }
  }
}
