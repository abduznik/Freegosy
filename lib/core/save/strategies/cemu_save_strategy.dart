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
    final saveRoot = Directory('$emuDir\\mlc01\\usr\\save');
    if (!await saveRoot.exists()) return [];
    return [File(saveRoot.path)];
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final emuDir = await _getEmulatorDir();
      if (emuDir == null) return false;

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        final folderName = filename.replaceAll('.zip', '');
        final targetBaseDir = '$emuDir\\mlc01\\usr\\save\\00050000\\$folderName';

        for (final entry in archive) {
          final targetPath = '$targetBaseDir\\${entry.name}';
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
      return false;
    } catch (e) {
      return false;
    }
  }
}
