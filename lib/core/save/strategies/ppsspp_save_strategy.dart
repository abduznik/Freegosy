import 'dart:io' as io;
import 'dart:io' show File;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
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

  Future<String> _getPspDir() async {
    // 1. Check portable mode first (Windows)
    if (io.Platform.isWindows) {
      final exePath = await _directoryService.findEmulatorExecutable(
          'ppsspp', 'PPSSPPWindows64.exe');
      if (exePath != null) {
        final emuDir = io.File(exePath).parent.path;
        final portableDir = p.join(emuDir, 'memstick', 'PSP');
        if (await io.Directory(portableDir).exists()) {
          return portableDir;
        }
      }
    }

    // 2. Dynamic path resolution
    final baseDir = await _directoryService.getEmulatorAppSupportDirectory('ppsspp');
    final pspDir = p.join(baseDir, 'PSP');

    if (!await io.Directory(pspDir).exists()) {
      throw Exception('Save directory not found for PPSSPP at $pspDir. Please launch PPSSPP at least once to generate save data.');
    }
    return pspDir;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final pspDir = await _getPspDir();
    return p.join(pspDir, 'SAVEDATA');
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final pspDir = await _getPspDir();

    final result = <File>[];
    final stem = getRomStem(game);

    final saveDataDir = io.Directory(p.join(pspDir, 'SAVEDATA'));
    if (await saveDataDir.exists()) {
      bool hasFiles = false;
      await for (final _ in saveDataDir.list(recursive: true)) {
        hasFiles = true;
        break;
      }
      if (hasFiles) {
        result.add(io.File(saveDataDir.path));
      }
    }

    final statesDir = io.Directory(p.join(pspDir, 'PPSSPP_STATE'));
    if (await statesDir.exists()) {
      final stateFile = io.File(p.join(pspDir, 'PPSSPP_STATE', '$stem.ppst'));
      if (await stateFile.exists()) {
        if (sessionStart == null ||
            (await stateFile.stat()).modified.isAfter(sessionStart)) {
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
      final pspDir = await _getPspDir();

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        final targetBaseDir = p.join(pspDir, 'SAVEDATA');
        for (final entry in archive) {
          if (entry.name.contains('.bak')) continue;
          final segments = entry.name.split('/');
          final strippedPath =
              segments.length > 1 ? segments.skip(1).join('/') : entry.name;
          if (strippedPath.isEmpty) continue;
          final targetPath = p.join(targetBaseDir, strippedPath);
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

      if (filename.toLowerCase().endsWith('.ppst')) {
        final targetPath = p.join(pspDir, 'PPSSPP_STATE', filename);
        await backupSave(targetPath);
        final outFile = io.File(targetPath);
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
