import 'dart:io';
import 'dart:io' as io;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class AzaharStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  AzaharStrategy(this._directoryService);

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
  String get linuxExecutable => 'azahar';

  @override
  String get macosExecutable => 'Azahar.app/Contents/MacOS/azahar';

  @override
  bool get supportsSaveSync => true;

  Future<void> _ensure3dsFonts(String azaharSystemDir) async {
    final fontFile = io.File(p.join(azaharSystemDir, 'sysdata', 'shared_font.bin'));
    if (await fontFile.exists()) return;

    debugPrint('[Azahar] Downloading 3DS shared font...');
    final dio = Dio();
    try {
      await dio.download(
        'https://github.com/citra-emu/citra-sysdata-mks/raw/master/shared_font.bin',
        fontFile.path,
      );
      debugPrint('[Azahar] 3DS shared font downloaded.');
    } catch (e) {
      debugPrint('[Azahar] Failed to download 3DS shared font: $e');
    }
  }

  Future<void> _ensure3dsSetup() async {
    final azaharSystemDir = await _directoryService.getEmulatorSystemDirectory(emulatorId);
    final sysdataDir = io.Directory(p.join(azaharSystemDir, 'sysdata'));
    final configDir = io.Directory(p.join(azaharSystemDir, 'config'));

    if (!await sysdataDir.exists()) await sysdataDir.create(recursive: true);
    if (!await configDir.exists()) await configDir.create(recursive: true);

    await _ensure3dsFonts(azaharSystemDir);

    debugPrint('[Azahar] 3DS setup ensured at $azaharSystemDir. Place your aes_keys.txt in ${sysdataDir.path}');
  }

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );

    if (io.Platform.isMacOS) {
      final emuDir = await _directoryService.getEmulatorDirectory(emulatorId);
      final appExists = await Directory('$emuDir/Azahar.app').exists();
      final dylibExists = await File('$emuDir/azahar_libretro.dylib').exists();

      if (!appExists && dylibExists) {
        throw Exception('Found Azahar Libretro core. Please switch to RetroArch in Settings to play this game.');
      }
    }

    if (exePath == null) throw Exception('$name not found. Please download it first.');

    if (io.Platform.isMacOS && exePath.endsWith('.dylib')) {
      throw Exception('Found Azahar Libretro core. Please switch to RetroArch in Settings to play this game.');
    }

    await _ensure3dsSetup();

    await Process.start(exePath, [romPath], mode: ProcessStartMode.detached);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );

    if (io.Platform.isMacOS) {
      final emuDir = await _directoryService.getEmulatorDirectory(emulatorId);
      final appExists = await Directory('$emuDir/Azahar.app').exists();
      final dylibExists = await File('$emuDir/azahar_libretro.dylib').exists();

      if (!appExists && dylibExists) {
        throw Exception('Found Azahar Libretro core. Please switch to RetroArch in Settings to play this game.');
      }
    }

    if (exePath == null) throw Exception('$name not found. Please download it first.');

    if (io.Platform.isMacOS && exePath.endsWith('.dylib')) {
      throw Exception('Found Azahar Libretro core. Please switch to RetroArch in Settings to play this game.');
    }

    await _ensure3dsSetup();

    return await Process.start(exePath, [romPath], mode: ProcessStartMode.normal);
  }

  @override
  String resolveSavePath(Game game) => '';
}
