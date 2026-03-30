import 'dart:io' as io;
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../save_strategy.dart';

/// Save strategy for mGBA (GBA/GBC/GB).
class MgbaSaveStrategy extends SaveStrategy {
  @override
  String get strategyId => 'mgba';

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    return io.File(romPath).parent.path;
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final romFile = io.File(romPath);
    final romStem = p.basenameWithoutExtension(romFile.path);
    final saveFile = io.File(p.join(romFile.parent.path, '$romStem.sav'));

    if (await saveFile.exists()) {
      if (sessionStart != null) {
        final stat = await saveFile.stat();
        if (stat.modified.isBefore(sessionStart)) return [];
      }
      return [saveFile];
    } else {
      // Fallback to getRomStem(game)
      final fallbackStem = getRomStem(game);
      final fallbackSaveFile = io.File(p.join(romFile.parent.path, '$fallbackStem.sav'));
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
      final romFile = io.File(destPath);
      final romStem = p.basenameWithoutExtension(romFile.path);
      final targetPath = p.join(romFile.parent.path, '$romStem.sav');

      // Prefer matching the actual ROM filename stem
      await backupSave(targetPath);
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}
