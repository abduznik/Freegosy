import 'dart:io' as io;
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for melonDS (Nintendo DS).
class MelonDsSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  MelonDsSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'melonds';

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    if (io.Platform.isLinux) {
      final emuDir = await _directoryService.getEmulatorAppSupportDirectory('melonds');
      if (await io.Directory(emuDir).exists()) return emuDir;
    }
    return io.File(romPath).parent.path;
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];

    final romStem = p.basenameWithoutExtension(romPath);
    final saveFile = io.File(p.join(saveDir, '$romStem.sav'));

    if (await saveFile.exists()) {
      if (sessionStart != null) {
        final stat = await saveFile.stat();
        if (stat.modified.isBefore(sessionStart)) return [];
      }
      return [saveFile];
    } else {
      // Fallback to getRomStem(game)
      final fallbackStem = getRomStem(game);
      final fallbackSaveFile = io.File(p.join(saveDir, '$fallbackStem.sav'));
      if (await fallbackSaveFile.exists()) {
        if (sessionStart != null) {
          final stat = await fallbackSaveFile.stat();
          if (stat.modified.isBefore(sessionStart)) return [];
        }
        return [fallbackSaveFile];
      }
    }
    return [];
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) return false;

      final romStem = p.basenameWithoutExtension(destPath);
      String targetPath = p.join(saveDir, '$romStem.sav');

      if (!await io.File(targetPath).exists()) {
        // Fallback to getRomStem(game)
        final fallbackStem = getRomStem(game);
        targetPath = p.join(saveDir, '$fallbackStem.sav');
      }

      await io.Directory(p.dirname(targetPath)).create(recursive: true);
      await backupSave(targetPath);
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}
