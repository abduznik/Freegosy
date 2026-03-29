import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class MAMEStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  MAMEStrategy(this._directoryService);

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
  Future<void> launch(Game game, String romPath) async {
    final emulatorDir = await _directoryService.getEmulatorDirectory(emulatorId);
    final mameExePath = await _directoryService.findEmulatorExecutable(
      emulatorId, windowsExecutable,
    );

    if (mameExePath == null) {
      // Check for self-extracting exe in the emulator directory
      final dir = Directory(emulatorDir);
      if (await dir.exists()) {
        final files = await dir.list().toList();
        final setupExe = files.firstWhere(
          (f) => f is File && f.path.toLowerCase().endsWith('.exe') && !f.path.toLowerCase().endsWith('mame.exe'),
          orElse: () => File(''),
        );

        if (setupExe.path.isNotEmpty) {
          // It's a self-extracting exe, run it to extract
          // We run it with current directory set to emulatorDir so it extracts there
          await Process.run(setupExe.path, [], workingDirectory: emulatorDir);
          
          // Try finding mame.exe again
          final retryPath = await _directoryService.findEmulatorExecutable(
            emulatorId, windowsExecutable,
          );
          if (retryPath != null) {
            await Process.start(retryPath, [romPath], mode: ProcessStartMode.detached);
            return;
          }
        }
      }
      throw Exception('$name not found. Please download it first.');
    }

    await Process.start(mameExePath, [romPath], mode: ProcessStartMode.detached);
  }

  @override
  Future<void> launchStandalone() async {
    final exePath = await _directoryService.findEmulatorExecutable(
      emulatorId, getExecutableForPlatform(),
    );
    if (exePath == null) throw Exception('$name not found. Please download it first.');
    await Process.start(exePath, [], mode: ProcessStartMode.detached);
  }

  @override
  String resolveSavePath(Game game) => '';
}
