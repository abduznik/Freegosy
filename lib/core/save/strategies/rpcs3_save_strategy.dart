import 'dart:io';
import 'dart:io' as io;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for RPCS3 (PlayStation 3).
/// Saves: {emulatorDir}\dev_hdd0\home\00000001\savedata\{titleId}\
class Rpcs3SaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  Rpcs3SaveStrategy(this._directoryService);

  @override
  String get strategyId => 'rpcs3';

  Future<String?> _getRpcs3SaveRoot() async {
    if (io.Platform.isMacOS) {
      final home = io.Platform.environment['HOME'];
      if (home == null) return null;
      return p.join(home, 'Library', 'Application Support', 'rpcs3', 'dev_hdd0', 'home', '00000001', 'savedata');
    }

    final exePath = await _directoryService.findEmulatorExecutable(
        'rpcs3', 'rpcs3.exe');
    if (exePath == null) return null;
    final exeDir = File(exePath).parent.path;
    return p.join(exeDir, 'dev_hdd0', 'home', '00000001', 'savedata');
  }

  /// Finds all save folders for this game by scanning savedata dir for
  /// folders starting with the title ID (e.g. BLUS30443 matches BLUS30443DEMONSS005)
  /// Finds save folders by scanning savedata dir.
  /// First tries title ID from ROM name, then falls back to
  /// fuzzy matching folder names against game name.
  Future<List<Directory>> _findSaveDirs(String saveRoot, Game game) async {
    final rootDir = Directory(saveRoot);
    if (!await rootDir.exists()) return [];

    final allDirs = <Directory>[];
    await for (final entity in rootDir.list()) {
      if (entity is Directory) allDirs.add(entity);
    }
    if (allDirs.isEmpty) return [];

    // Method 1: title ID from ROM filename
    final name = game.fsName ?? game.fileName ?? game.name;
    final match = RegExp(r'[A-Z]{4}\d{5}').firstMatch(name.toUpperCase());
    if (match != null) {
      final titleId = match.group(0)!;
      final byTitleId = allDirs.where((d) {
        final folderName = d.path.split(p.separator).last.toUpperCase();
        return folderName.startsWith(titleId);
      }).toList();
      if (byTitleId.isNotEmpty) {
        return byTitleId;
      }
    }

    // Method 2: fuzzy match — folder name contains words from game name
    final gameWords = game.name
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), '')
        .split(' ')
        .where((w) => w.length > 3)
        .toList();

    final byName = allDirs.where((d) {
      final folderLower = d.path.split(p.separator).last.toLowerCase();
      return gameWords.any((word) => folderLower.contains(word));
    }).toList();

    if (byName.isNotEmpty) {
      return byName;
    }

    return [];
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final saveRoot = await _getRpcs3SaveRoot();
    if (saveRoot == null) return null;
    final dirs = await _findSaveDirs(saveRoot, game);
    return dirs.isNotEmpty ? dirs.first.path : null;
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveRoot = await _getRpcs3SaveRoot();
    if (saveRoot == null) return [];

    final saveDirs = await _findSaveDirs(saveRoot, game);
    if (saveDirs.isEmpty) {
      return [];
    }

    // Package all matching save folders into a single zip
    bool hasFiles = false;
    for (final dir in saveDirs) {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        if (sessionStart != null) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(sessionStart)) continue;
        }
        hasFiles = true;
        break;
      }
      if (hasFiles) break;
    }
    if (!hasFiles) return [];

    final zipPath = p.join(saveRoot, '${game.id}.saves.zip');
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    for (final dir in saveDirs) {
      await encoder.addDirectory(dir);
    }
    encoder.close();

    return [File(zipPath)];
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final saveRoot = await _getRpcs3SaveRoot();
      if (saveRoot == null) return false;

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          final entryPath = p.join(saveRoot, entry.name);
          if (entry.isFile) {
            await backupSave(entryPath);
            final outFile = File(entryPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          } else {
            await Directory(entryPath).create(recursive: true);
          }
        }
        return true;
      }

      // Fallback single file
      final saveDir = await getSaveDir(game, destPath) ?? saveRoot;
      await Directory(saveDir).create(recursive: true);
      final targetPath = p.join(saveDir, filename);
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}
