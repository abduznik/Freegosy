import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for DuckStation (PlayStation 1).
class DuckstationSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  DuckstationSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'duckstation';

  Future<String?> _getBaseDir() async {
    final exePath = await _directoryService.findEmulatorExecutable(
        'duckstation', 'duckstation-qt-x64-ReleaseLTCG.exe');
    if (exePath == null) return null;
    final emulatorDir = File(exePath).parent.path.replaceAll('/', '\\');

    if (await File('$emulatorDir\\portable.txt').exists()) {
      return emulatorDir;
    }

    try {
      final result = await Process.run('cmd', ['/c', 'echo %LOCALAPPDATA%'], runInShell: false);
      final localAppData = result.stdout.toString().trim();
      if (localAppData.isNotEmpty && !localAppData.contains('%')) {
        return '$localAppData\\DuckStation';
      }
    } catch (e) {
      // ignore
    }
    return emulatorDir;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final baseDir = await _getBaseDir();
    if (baseDir == null) return null;
    return '$baseDir\\memcards';
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final baseDir = await _getBaseDir();
    if (baseDir == null) return [];

    final result = <File>[];
    final stem = getRomStem(game);

    final memcardsDir = Directory('$baseDir\\memcards');
    if (await memcardsDir.exists()) {
      await for (final entity in memcardsDir.list()) {
        if (entity is File &&
            entity.path.toLowerCase().contains(stem.toLowerCase()) &&
            entity.path.toLowerCase().endsWith('.mcd')) {
          if (sessionStart != null) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(sessionStart)) continue;
          }
          result.add(entity);
        }
      }
    }

    final statesDir = Directory('$baseDir\\savestates');
    if (await statesDir.exists()) {
      await for (final entity in statesDir.list()) {
        if (entity is File && entity.path.toLowerCase().contains(stem.toLowerCase())) {
          if (sessionStart != null) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(sessionStart)) continue;
          }
          result.add(entity);
        }
      }
    }

    return result;
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final baseDir = await _getBaseDir();
      if (baseDir == null) return false;

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          if (!entry.isFile) continue;
          final entryLower = entry.name.toLowerCase();
          final targetDir = entryLower.endsWith('.mcd')
              ? '$baseDir\\memcards'
              : '$baseDir\\savestates';

          final targetPath = '$targetDir\\${entry.name.split('\\').last.split('/').last}';
          await backupSave(targetPath);
          final outFile = File(targetPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
        }
        return true;
      }

      final isState = !filename.toLowerCase().endsWith('.mcd');
      final targetDir = isState ? '$baseDir\\savestates' : '$baseDir\\memcards';
      final targetPath = '$targetDir\\$filename';
      await Directory(targetDir).create(recursive: true);
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}
