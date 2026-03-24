import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for Xenia Canary (Xbox 360).
/// Saves: {emulatorDir}\content\{titleId}\00000001\
class XeniaSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  XeniaSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'xenia_canary';

  /// Xbox 360 title IDs are 8 hex characters e.g. 4D5307E6
  String? _extractTitleId(Game game) {
    final name = game.fsName ?? game.fileName ?? game.name;
    final match = RegExp(r'[0-9A-Fa-f]{8}').firstMatch(name);
    return match?.group(0)?.toUpperCase();
  }

  Future<String?> _getContentDir() async {
    final exePath = await _directoryService.findEmulatorExecutable(
        'xenia_canary', 'xenia_canary.exe');
    if (exePath == null) return null;
    return '${File(exePath).parent.path}\\content';
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final contentDir = await _getContentDir();
    if (contentDir == null) return null;
    final titleId = _extractTitleId(game);
    if (titleId == null) return null;
    return '$contentDir\\$titleId\\00000001';
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];

    final dir = Directory(saveDir);
    if (!await dir.exists()) return [];

    bool hasFiles = false;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      if (sessionStart != null) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(sessionStart)) continue;
      }
      hasFiles = true;
      break;
    }
    if (!hasFiles) return [];

    // Package entire save folder as zip
    final zipPath = '${dir.path}.saves.zip';
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await encoder.addDirectory(dir);
    encoder.close();

    debugPrint('[XeniaSaveStrategy] packaged saves to $zipPath');
    return [File(zipPath)];
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) return false;

      await Directory(saveDir).create(recursive: true);

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          final entryPath = '$saveDir\\${entry.name}';
          if (entry.isFile) {
            await backupSave(entryPath);
            final outFile = File(entryPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          } else {
            await Directory(entryPath).create(recursive: true);
          }
        }
        debugPrint('[XeniaSaveStrategy] extracted $filename to $saveDir');
        return true;
      }

      final targetPath = '$saveDir\\$filename';
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      debugPrint('[XeniaSaveStrategy] restored $filename to $targetPath');
      return true;
    } catch (e) {
      debugPrint('[XeniaSaveStrategy] restoreSave error: $e');
      return false;
    }
  }
}