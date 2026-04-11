import 'dart:io';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for DuckStation (PlayStation 1).
class DuckstationSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  DuckstationSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'duckstation';

  Future<String> _getBaseDir({String? platformSlug}) async {
    // 1. Check portable mode first (Windows)
    final exePath = await _directoryService.findEmulatorExecutable(
        'duckstation', 'duckstation-qt-x64-ReleaseLTCG.exe');
    if (exePath != null) {
      final emulatorDir = File(exePath).parent.path;
      if (await File(p.join(emulatorDir, 'portable.txt')).exists()) {
        return emulatorDir;
      }
    }

    // 2. Dynamic path resolution for macOS/Windows/Linux
    final String resolvedPath;
    if (io.Platform.isWindows) {
      final localAppData = io.Platform.environment['LOCALAPPDATA'] ?? '';
      resolvedPath = p.join(localAppData, 'DuckStation');
    } else {
      resolvedPath = await _directoryService.getEmulatorAppSupportDirectory('DuckStation', platformSlug: platformSlug);
    }

    if (!await io.Directory(resolvedPath).exists()) {
      throw Exception('Save directory not found for DuckStation at $resolvedPath. Please launch DuckStation at least once to generate save data.');
    }
    return resolvedPath;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final baseDir = await _getBaseDir(platformSlug: game.platformSlug);
    return p.join(baseDir, 'memcards');
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final baseDir = await _getBaseDir(platformSlug: game.platformSlug);

    final result = <File>[];
    final stem = getRomStem(game);

    final memcardsDir = Directory(p.join(baseDir, 'memcards'));
    if (await memcardsDir.exists()) {
      await for (final entity in memcardsDir.list()) {
        if (entity is File &&
            p.basename(entity.path).toLowerCase().contains(stem.toLowerCase()) &&
            entity.path.toLowerCase().endsWith('.mcd')) {
          if (sessionStart != null) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(sessionStart)) continue;
          }
          result.add(entity);
        }
      }
    }

    final statesDir = Directory(p.join(baseDir, 'savestates'));
    if (await statesDir.exists()) {
      await for (final entity in statesDir.list()) {
        if (entity is File && p.basename(entity.path).toLowerCase().contains(stem.toLowerCase())) {
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
      final baseDir = await _getBaseDir(platformSlug: game.platformSlug);

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          if (!entry.isFile) continue;
          final entryLower = entry.name.toLowerCase();
          final targetDirName = entryLower.endsWith('.mcd')
              ? 'memcards'
              : 'savestates';
          final targetDir = p.join(baseDir, targetDirName);

          final targetPath = p.join(targetDir, p.basename(entry.name));
          await backupSave(targetPath);
          final outFile = File(targetPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
        }
        return true;
      }

      final isState = !filename.toLowerCase().endsWith('.mcd');
      final targetDirName = isState ? 'savestates' : 'memcards';
      final targetPath = p.join(baseDir, targetDirName, filename);
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}
