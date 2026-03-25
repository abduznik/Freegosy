import 'dart:io';
import 'dart:typed_data';
import '../../romm/romm_models.dart';
import '../save_strategy.dart';

/// Save strategy for mGBA (GBA/GBC/GB).
class MgbaSaveStrategy extends SaveStrategy {
  @override
  String get strategyId => 'mgba';

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    return File(romPath).parent.path;
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final stem = getRomStem(game);
    final saveFile = File('${File(romPath).parent.path}/$stem.sav');

    if (await saveFile.exists()) {
      if (sessionStart != null) {
        final stat = await saveFile.stat();
        if (stat.modified.isBefore(sessionStart)) return [];
      }
      return [saveFile];
    }
    return [];
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final stem = getRomStem(game);
      final targetPath = '${File(destPath).parent.path}/$stem.sav';
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}
