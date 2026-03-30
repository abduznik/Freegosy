import 'dart:io' as io;
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
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
    if (!await io.Directory(dir).exists()) return null;
    return dir;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final emuDir = await _getEmulatorDir();
    if (emuDir == null) return null;
    return p.join(emuDir, 'mlc01', 'usr', 'save');
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final emuDir = await _getEmulatorDir();
    if (emuDir == null) return [];
    final saveRoot = io.Directory(p.join(emuDir, 'mlc01', 'usr', 'save', '00050000'));
    if (!await saveRoot.exists()) return [];
    return [io.File(saveRoot.path)]; // Return the directory as a single item
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final emuDir = await _getEmulatorDir();
      if (emuDir == null) return false;
      final saveRoot = p.join(emuDir, 'mlc01', 'usr', 'save');
      await io.Directory(saveRoot).create(recursive: true);
      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          if (entry.name.contains('.bak')) continue;
          final entryName = entry.name;
          if (entryName.isEmpty || entryName.endsWith('/') || entryName.endsWith('\\')) continue;
          final targetPath = p.join(saveRoot, entryName);
          if (entry.isFile) {
            await backupSave(targetPath);
            final outFile = io.File(targetPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          } else {
            await io.Directory(targetPath).create(recursive: true);
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
