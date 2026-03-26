import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for PPSSPP (PSP).
class PpssppSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  PpssppSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'ppsspp';

  Future<String?> _getEmulatorDir() async {
    final exePath = await _directoryService.findEmulatorExecutable(
        'ppsspp', 'PPSSPPWindows64.exe');
    if (exePath == null) return null;
    return File(exePath).parent.path.replaceAll('/', '\\');
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final emuDir = await _getEmulatorDir();
    if (emuDir == null) return null;
    return '$emuDir\\memstick\\PSP\\SAVEDATA';
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final emuDir = await _getEmulatorDir();
    if (emuDir == null) return [];

    final result = <File>[];
    final stem = getRomStem(game);

    final saveDataDir = Directory('$emuDir\\memstick\\PSP\\SAVEDATA');
    if (await saveDataDir.exists()) {
      bool hasFiles = false;
      await for (final _ in saveDataDir.list(recursive: true)) {
        hasFiles = true;
        break;
      }
      if (hasFiles) {
        result.add(File(saveDataDir.path));
      }
    }

    final statesDir = Directory('$emuDir\\memstick\\PSP\\PPSSPP_STATE');
    if (await statesDir.exists()) {
      final stateFile = File('${statesDir.path}\\$stem.ppst');
      if (await stateFile.exists()) {
        if (sessionStart == null || (await stateFile.stat()).modified.isAfter(sessionStart)) {
          result.add(stateFile);
        }
      }
    }

    return result;
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final emuDir = await _getEmulatorDir();
      if (emuDir == null) return false;

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        final targetBaseDir = '$emuDir\\memstick\\PSP\\SAVEDATA';
        for (final entry in archive) {
          if (entry.name.contains('.bak')) continue;
          final entryPath = entry.name.replaceAll('/', '\\');
          final segments = entryPath.split('\\');
          final strippedPath = segments.length > 1 ? segments.skip(1).join('\\') : entryPath;
          if (strippedPath.isEmpty) continue;
          final targetPath = '$targetBaseDir\\$strippedPath';
          if (entry.isFile) {
            await backupSave(targetPath);
            final outFile = File(targetPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          } else {
            await Directory(targetPath).create(recursive: true);
          }
        }
        return true;
      }

      if (filename.toLowerCase().endsWith('.ppst')) {
        final targetPath = '$emuDir\\memstick\\PSP\\PPSSPP_STATE\\$filename';
        await backupSave(targetPath);
        final outFile = File(targetPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(data);
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }
}
