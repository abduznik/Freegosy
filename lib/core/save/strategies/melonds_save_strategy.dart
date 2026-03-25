import 'dart:io';
import 'dart:typed_data';
import '../../romm/romm_models.dart';
import '../save_strategy.dart';

/// Save strategy for melonDS (Nintendo DS).
class MelonDsSaveStrategy extends SaveStrategy {
  @override
  String get strategyId => 'melonds';

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    return File(romPath).parent.path;
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final romFile = File(romPath);
    final romStem = romFile.uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '');
    final saveFile = File('${File(romPath).parent.path}/$romStem.sav');

    if (await saveFile.exists()) {
      if (sessionStart != null) {
        final stat = await saveFile.stat();
        if (stat.modified.isBefore(sessionStart)) return [];
      }
      return [saveFile];
    } else {
      // Fallback to getRomStem(game)
      final fallbackStem = getRomStem(game);
      final fallbackSaveFile = File('${File(romPath).parent.path}/$fallbackStem.sav');
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
      final romFile = File(destPath);
      final romStem = romFile.uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      final targetPath = '${File(destPath).parent.path}/$romStem.sav';

      if (await File(targetPath).exists()) {
        await backupSave(targetPath);
        await File(targetPath).writeAsBytes(data);
        return true;
      } else {
        // Fallback to getRomStem(game)
        final fallbackStem = getRomStem(game);
        final fallbackTargetPath = '${File(destPath).parent.path}/$fallbackStem.sav';
        await backupSave(fallbackTargetPath);
        await File(fallbackTargetPath).writeAsBytes(data);
        return true;
      }
    } catch (e) {
      return false;
    }
  }
}
