import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import '../emulator_strategy.dart';
import '../custom_emulator_config.dart';

class CustomEmulatorStrategy extends EmulatorStrategy {
  final CustomEmulatorConfig config;
  @override
  final DirectoryService directoryService;

  CustomEmulatorStrategy(this.config, this.directoryService);

  @override
  String get name => config.name;

  @override
  String get emulatorId => config.id;

  @override
  List<String> get supportedSlugs => config.platforms;

  @override
  String get windowsExecutable => config.executablePath;

  @override
  String get linuxExecutable => config.executablePath;

  @override
  bool get supportsSaveSync => true;

  @override
  Future<String?> findExecutable() async {
    // For custom emulators, the user provides the absolute path.
    if (await io.File(config.executablePath).exists()) {
      return config.executablePath;
    }
    return null;
  }

  @override
  String resolveSavePath(Game game) {
    if (config.saveMethod == CustomSaveMethod.file) {
      final pattern = config.savePattern ?? '';
      if (pattern.contains('*')) {
        final ext = pattern.replaceAll('*', '');
        return p.join(config.savePath, '${game.displayName}$ext');
      } else if (pattern.isNotEmpty) {
        return p.join(config.savePath, pattern);
      } else {
        // Fallback: just game name
        return p.join(config.savePath, game.displayName);
      }
    } else {
      // Folder based
      return p.join(config.savePath, game.displayName);
    }
  }

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('Custom emulator executable not found at: ${config.executablePath}');

    final normalizedRomPath = p.absolute(p.normalize(romPath));
    
    // We use a raw process start because custom emulators might not be in the standard EmuDeck structure
    await io.Process.run(exePath, [normalizedRomPath], runInShell: true);
  }
}
