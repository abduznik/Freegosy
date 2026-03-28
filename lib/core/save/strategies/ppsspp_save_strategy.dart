import 'dart:io' as io;
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for PPSSPP (PSP).
class PpssppSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  PpssppSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'ppsspp';

  /// Returns the PPSSPP memstick PSP root directory for the current platform.
  Future<String?> _getPspDir() async {
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux) {
      // PPSSPP SDL on macOS/Linux uses ~/.config/ppsspp/PSP
      final home = io.Platform.environment['HOME'];
      if (home == null) return null;
      return '$home/.config/ppsspp/PSP';
    } else {
      // Windows: saves are relative to the executable
      final exePath = await _directoryService.findEmulatorExecutable(
          'ppsspp', 'PPSSPPWindows64.exe');
      if (exePath == null) return null;
      final emuDir = io.File(exePath).parent.path;
      return '$emuDir\\memstick\\PSP';
    }
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final pspDir = await _getPspDir();
    if (pspDir == null) return null;
    final sep = io.Platform.isWindows ? '\\' : '/';
    return '$pspDir${sep}SAVEDATA';
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final pspDir = await _getPspDir();
    if (pspDir == null) return [];

    final sep = io.Platform.isWindows ? '\\' : '/';
    final result = <File>[];
    final stem = getRomStem(game);

    final saveDataDir = io.Directory('$pspDir${sep}SAVEDATA');
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

    final statesDir = io.Directory('$pspDir${sep}PPSSPP_STATE');
    if (await statesDir.exists()) {
      final stateFile = io.File('$pspDir${sep}PPSSPP_STATE${sep}$stem.ppst');
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
      if (pspDir == null) return false;

      final sep = io.Platform.isWindows ? '\\' : '/';

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        final targetBaseDir = '$pspDir${sep}SAVEDATA';
        for (final entry in archive) {
          if (entry.name.contains('.bak')) continue;
          final entryPath = entry.name.replaceAll('/', sep);
          final segments = entryPath.split(sep);
          final strippedPath =
              segments.length > 1 ? segments.skip(1).join(sep) : entryPath;
          if (strippedPath.isEmpty) continue;
          final targetPath = '$targetBaseDir$sep$strippedPath';
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
        final targetPath = '$pspDir${sep}PPSSPP_STATE$sep$filename';
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
