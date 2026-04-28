import 'dart:io' as io;
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for mGBA (GBA/GBC/GB).
class MgbaSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  MgbaSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'mgba';

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    if (io.Platform.isLinux) {
      final emuDir = await _directoryService.getEmulatorAppSupportDirectory('mgba');
      if (await io.Directory(emuDir).exists()) return emuDir;
    }
    return io.File(romPath).parent.path;
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];

    final romStem = p.basenameWithoutExtension(romPath).toLowerCase();
    final fallbackStem = getRomStem(game).toLowerCase();
    
    final dir = io.Directory(saveDir);
    if (!await dir.exists()) return [];

    final List<io.File> foundFiles = [];
    await for (final entity in dir.list()) {
      if (entity is! io.File) continue;
      final fname = p.basename(entity.path).toLowerCase();
      if ((fname == '$romStem.sav' || fname == '$fallbackStem.sav')) {
        if (sessionStart != null) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(sessionStart)) continue;
        }
        foundFiles.add(entity);
        break; 
      }
    }
    return foundFiles;
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) return false;

      final romStem = p.basenameWithoutExtension(destPath).toLowerCase();
      final fallbackStem = getRomStem(game).toLowerCase();
      String targetPath = p.normalize(p.join(saveDir, '$romStem.sav'));

      final dir = io.Directory(saveDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is! io.File) continue;
          final fname = p.basename(entity.path).toLowerCase();
          if (fname == '$romStem.sav' || fname == '$fallbackStem.sav') {
            targetPath = entity.path;
            break;
          }
        }
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
