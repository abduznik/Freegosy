import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for Cemu (Wii U).
class CemuSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  CemuSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'cemu';

  Future<String?> _getEmulatorDir() async {
    final dir = await _directoryService.getEmulatorDirectory('cemu');
    if (!await Directory(dir).exists()) return null;
    return dir.replaceAll('/', '\\');
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final emuDir = await _getEmulatorDir();
    if (emuDir == null) return null;
    return '$emuDir\\mlc01\\usr\\save';
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final emuDir = await _getEmulatorDir();
    if (emuDir == null) return [];
    final saveRoot = Directory('$emuDir\\mlc01\\usr\\save\\00050000');
    if (!await saveRoot.exists()) return [];
    return [File(saveRoot.path)]; // Return the directory as a single item
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final emuDir = await _getEmulatorDir();
      if (emuDir == null) return false;
      final saveRoot = '$emuDir\\mlc01\\usr\\save';
      await Directory(saveRoot).create(recursive: true);
      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          if (entry.name.contains('.bak')) continue;
          final entryPath = entry.name.replaceAll('/', '\\');
          if (entryPath.isEmpty || entryPath.endsWith('\\')) continue;
          final targetPath = '$saveRoot\\$entryPath';          if (entry.isFile) {
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
      return false;
    } catch (e) {
      return false;
    }
  }
}