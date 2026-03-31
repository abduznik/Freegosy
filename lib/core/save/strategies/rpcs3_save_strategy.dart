import 'dart:io';
import 'dart:io' as io;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

class SaveFolderConflictException implements Exception {
  final List<Map<String, dynamic>> folders;
  SaveFolderConflictException(this.folders);
  @override
  String toString() =>
      'SaveFolderConflictException: ${folders.length} matching save folders found.';
}

/// Save strategy for RPCS3 (PlayStation 3).
/// Saves: {emulatorDir}\dev_hdd0\home\00000001\savedata\{titleId}\
class Rpcs3SaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  String? _activeFolderOverride;
  void setActiveFolderOverride(String? path) => _activeFolderOverride = path;

  Rpcs3SaveStrategy(this._directoryService);

  @override
  String get strategyId => 'rpcs3';

  Future<String> _getRpcs3SaveRoot() async {
    // 1. Check portable mode first (Windows)
    final exePath = await _directoryService.findEmulatorExecutable(
        'rpcs3', 'rpcs3.exe');
    if (exePath != null) {
      final exeDir = File(exePath).parent.path;
      final portableSaves = p.join(exeDir, 'dev_hdd0', 'home', '00000001', 'savedata');
      if (await io.Directory(portableSaves).exists()) {
        return portableSaves;
      }
    }

    // 2. Dynamic path resolution
    final baseDir = await _directoryService.getEmulatorAppSupportDirectory('rpcs3');
    final resolvedPath = p.join(baseDir, 'dev_hdd0', 'home', '00000001', 'savedata');

    if (!await io.Directory(resolvedPath).exists()) {
      throw Exception('Save directory not found for RPCS3 at $resolvedPath. Please launch RPCS3 at least once to generate save data.');
    }
    return resolvedPath;
  }

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
        .where((w) => w.length >= 2)
        .toList();

    final byName = allDirs.where((d) {
      final folderLower = d.path.split(p.separator).last.toLowerCase();
      return gameWords.any((word) => folderLower.contains(word));
    }).toList();

    if (byName.isEmpty) return [];

    // Single match — done
    if (byName.length == 1) {
      return byName;
    }

    // Method 3: multiple fuzzy matches — auto-pick most recently modified
    
    final withTimes = <Map<String, dynamic>>[];
    for (final dir in byName) {
      DateTime? latestFile;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (latestFile == null || stat.modified.isAfter(latestFile)) {
          latestFile = stat.modified;
        }
      }
      if (latestFile != null) {
        withTimes.add({
          'dir': dir,
          'path': dir.path,
          'name': dir.path.split(p.separator).last,
          'newestFile': latestFile,
        });
      }
    }

    if (withTimes.isEmpty) return [byName.first];

    // Sort by most recent
    withTimes.sort((a, b) => (b['newestFile'] as DateTime)
        .compareTo(a['newestFile'] as DateTime));

    final winner = withTimes[0];
    final runnerUp = withTimes[1];
    final gap = (winner['newestFile'] as DateTime)
        .difference(runnerUp['newestFile'] as DateTime);

    // Auto-pick if winner is clearly ahead (>1h gap)
    if (gap.inHours >= 1) {
      return [winner['dir'] as Directory];
    }

    // Method 4: genuine conflict — throw for UI to handle
    throw SaveFolderConflictException(withTimes
        .map((e) => {
              'name': e['name'] as String,
              'path': e['path'] as String,
              'newestFile': e['newestFile'] as DateTime,
            })
        .toList());
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    // Manual override from conflict dialog
    if (_activeFolderOverride != null) {
      return _activeFolderOverride;
    }
    final saveRoot = await _getRpcs3SaveRoot();
    final dirs = await _findSaveDirs(saveRoot, game);
    return dirs.isNotEmpty ? dirs.first.path : null;
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveRoot = await _getRpcs3SaveRoot();

    // Manual override — wrap single dir
    List<Directory> saveDirs;
    if (_activeFolderOverride != null) {
      saveDirs = [Directory(_activeFolderOverride!)];
    } else {
      saveDirs = await _findSaveDirs(saveRoot, game);
    }

    if (saveDirs.isEmpty) return [];

    // Check if any files exist (respecting sessionStart)
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