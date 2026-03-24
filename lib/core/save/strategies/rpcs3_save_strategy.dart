import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import '../../romm/romm_models.dart';
import '../save_strategy.dart';

/// Save strategy for RPCS3 (PlayStation 3).
/// Saves: %APPDATA%\rpcs3\dev_hdd0\home\00000001\savedata\{titleId}\
class Rpcs3SaveStrategy extends SaveStrategy {
  @override
  String get strategyId => 'rpcs3';

  Future<String?> _getRpcs3SaveRoot() async {
    try {
      final result = await Process.run(
        'cmd', ['/c', 'echo %APPDATA%'],
        runInShell: false,
      );
      final appData = result.stdout.toString().trim();
      if (appData.isEmpty || appData.contains('%APPDATA%')) return null;
      return '$appData\\rpcs3\\dev_hdd0\\home\\00000001\\savedata';
    } catch (e) {
      debugPrint('[Rpcs3SaveStrategy] failed to get APPDATA: $e');
      return null;
    }
  }

  /// PS3 title IDs are in the ROM folder name e.g. BLES01234
  String? _extractTitleId(Game game) {
    final name = game.fsName ?? game.fileName ?? game.name;
    final match = RegExp(r'[A-Z]{4}\d{5}').firstMatch(name.toUpperCase());
    return match?.group(0);
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final saveRoot = await _getRpcs3SaveRoot();
    if (saveRoot == null) return null;
    final titleId = _extractTitleId(game);
    if (titleId == null) return null;
    return '$saveRoot\\$titleId';
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveRoot = await _getRpcs3SaveRoot();
    if (saveRoot == null) return [];

    final titleId = _extractTitleId(game);
    if (titleId == null) {
      debugPrint('[Rpcs3SaveStrategy] could not extract title ID for ${game.name}');
      return [];
    }

    final saveDir = Directory('$saveRoot\\$titleId');
    if (!await saveDir.exists()) return [];

    // Package entire save folder as zip (same approach as Windows saves)
    bool hasFiles = false;
    await for (final entity in saveDir.list(recursive: true)) {
      if (entity is! File) continue;
      if (sessionStart != null) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(sessionStart)) continue;
      }
      hasFiles = true;
      break;
    }
    if (!hasFiles) return [];

    final zipPath = '${saveDir.path}.saves.zip';
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await encoder.addDirectory(saveDir);
    encoder.close();

    debugPrint('[Rpcs3SaveStrategy] packaged saves to $zipPath');
    return [File(zipPath)];
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final saveRoot = await _getRpcs3SaveRoot();
      if (saveRoot == null) return false;

      final titleId = _extractTitleId(game);
      if (titleId == null) return false;

      final saveDir = '$saveRoot\\$titleId';
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
        debugPrint('[Rpcs3SaveStrategy] extracted $filename to $saveDir');
        return true;
      }

      final targetPath = '$saveDir\\$filename';
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      debugPrint('[Rpcs3SaveStrategy] restored $filename to $targetPath');
      return true;
    } catch (e) {
      debugPrint('[Rpcs3SaveStrategy] restoreSave error: $e');
      return false;
    }
  }
}