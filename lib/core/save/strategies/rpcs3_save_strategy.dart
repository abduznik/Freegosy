import 'dart:convert';
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

  Future<String?> _readParamSfoTitle(String folderPath) async {
    try {
      final sfoFile = io.File(p.join(folderPath, 'PARAM.SFO'));
      if (!await sfoFile.exists()) return null;

      final bytes = await sfoFile.readAsBytes();
      if (bytes.length < 20) return null;

      final byteData = ByteData.view(bytes.buffer);

      if (bytes[0] != 0x00 || bytes[1] != 0x50 ||
          bytes[2] != 0x53 || bytes[3] != 0x46) {
        return null;
      }

      final keyTableOffset  = byteData.getUint32(8,  Endian.little);
      final dataTableOffset = byteData.getUint32(12, Endian.little);
      final entriesCount    = byteData.getUint32(16, Endian.little);

      for (int i = 0; i < entriesCount; i++) {
        final entryBase = 20 + i * 16;
        if (entryBase + 16 > bytes.length) break;

        final keyRelOffset  = byteData.getUint16(entryBase + 0,  Endian.little);
        final dataLen       = byteData.getUint32(entryBase + 4,  Endian.little);
        final dataRelOffset = byteData.getUint32(entryBase + 12, Endian.little);

        final keyStart = keyTableOffset + keyRelOffset;
        final keyBytes = <int>[];
        int j = keyStart;
        while (j < bytes.length && bytes[j] != 0) {
          keyBytes.add(bytes[j++]);
        }
        final key = utf8.decode(keyBytes);

        if (key == 'TITLE') {
          final valueStart = dataTableOffset + dataRelOffset;
          final valueEnd   = valueStart + dataLen;
          if (valueEnd > bytes.length) return null;

          final titleBytes = bytes.sublist(valueStart, valueEnd);
          final nullIdx = titleBytes.indexOf(0);
          final actual  = nullIdx != -1 ? titleBytes.sublist(0, nullIdx) : titleBytes;
          return utf8.decode(actual);
        }
      }

      return null;
    } catch (e) {
      debugPrint('[RPCS3] Error reading PARAM.SFO: $e');
      return null;
    }
  }

  String _getEmuExe() {
    if (io.Platform.isWindows) return 'rpcs3.exe';
    if (io.Platform.isMacOS) return 'RPCS3.app/Contents/MacOS/RPCS3';
    return 'rpcs3';
  }

  Future<String> _getRpcs3SaveRoot({String? platformSlug}) async {
    // 1. Check portable mode first (Windows)
    final exePath = await _directoryService.findEmulatorExecutable(
        'rpcs3', _getEmuExe());
    if (exePath != null) {
      String exeDir = File(exePath).parent.path;
      if (io.Platform.isMacOS && exePath.contains('.app/Contents/MacOS/')) {
        exeDir = io.File(exePath).parent.parent.parent.parent.path;
      }
      final portableSaves = p.join(exeDir, 'dev_hdd0', 'home', '00000001', 'savedata');
      if (await io.Directory(portableSaves).exists()) {
        return portableSaves;
      }
    }

    // 2. Dynamic path resolution
    final baseDir = await _directoryService.getEmulatorAppSupportDirectory('rpcs3', platformSlug: platformSlug);
    
    String resolvedPath;
    if (io.Platform.isLinux && p.basename(baseDir) == 'saves') {
      // EmuDeck mapping already points to the saves (savedata) symlink
      resolvedPath = baseDir;
    } else {
      resolvedPath = p.join(baseDir, 'dev_hdd0', 'home', '00000001', 'savedata');
    }

    if (!await io.Directory(resolvedPath).exists()) {
      throw Exception('Save directory not found for RPCS3 at $resolvedPath. Please launch RPCS3 at least once to generate save data.');
    }
    return resolvedPath;
  }

  Future<List<Directory>> _findSaveDirs(String saveRoot, Game game) async {
    final cleanGameName = game.displayName;
    final gameWords = cleanGameName
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .split(' ')
        .where((w) => w.length >= 2)
        .toList();

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

    // Method 2: PARAM.SFO title matching with scoring
    final sfoMatches = <Directory, int>{};
    for (final dir in allDirs) {
      final title = await _readParamSfoTitle(dir.path);
      if (title == null) continue;
      
      final titleLower = title.toLowerCase().replaceAll(RegExp(r"[^a-z0-9\s]"), ' ');
      final titleWords = titleLower.split(' ').where((w) => w.length >= 2).toSet();
      
      int score = 0;
      for (final word in gameWords) {
        if (titleWords.contains(word)) {
          score++;
        }
      }
      
      debugPrint('[RPCS3] PARAM.SFO title for ${dir.path.split(p.separator).last}: $title (Score: $score)');
      if (score > 0) {
        sfoMatches[dir] = score;
      }
    }

    if (sfoMatches.isNotEmpty) {
      final maxScore = sfoMatches.values.reduce((a, b) => a > b ? a : b);
      // Only keep matches with the highest score
      final bySfo = sfoMatches.entries
          .where((e) => e.value == maxScore)
          .map((e) => e.key)
          .toList();

      if (bySfo.length == 1) {
        debugPrint('[RPCS3] Method 2 PARAM.SFO single best match: ${bySfo.first.path}');
        return bySfo;
      }

      // If all matches share the same Title ID prefix (first 9 chars), return all of them.
      // RPCS3 often uses multiple folders for the same game (e.g. BLUS12345, BLUS12345F, BLUS12345L01).
      final titleIdRegExp = RegExp(r'^([A-Z]{4}\d{5})');
      final titleIds = bySfo.map((d) {
        final folderName = d.path.split(p.separator).last.toUpperCase();
        final match = titleIdRegExp.firstMatch(folderName);
        return match?.group(1) ?? folderName;
      }).toSet();

      if (titleIds.length == 1) {
        debugPrint('[RPCS3] Method 2 multiple matches for same Title ID ${titleIds.first}: returning all');
        return bySfo;
      }
      
      // Multiple SFO matches with same score but different Title IDs — fall through to recency/conflict logic
      final withTimes = <Map<String, dynamic>>[];
      for (final dir in bySfo) {
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
      if (withTimes.isNotEmpty) {
        withTimes.sort((a, b) => (b['newestFile'] as DateTime)
            .compareTo(a['newestFile'] as DateTime));
        
        if (withTimes.length == 1) return [withTimes[0]['dir'] as Directory];

        final winner = withTimes[0];
        final runnerUp = withTimes[1];
        final gap = (winner['newestFile'] as DateTime)
            .difference(runnerUp['newestFile'] as DateTime);
        if (gap.inHours >= 1) {
          return [winner['dir'] as Directory];
        }
        throw SaveFolderConflictException(withTimes
            .map((e) => {
                  'name': e['name'] as String,
                  'path': e['path'] as String,
                  'newestFile': e['newestFile'] as DateTime,
                })
            .toList());
      }
    }

    final byName = allDirs.where((d) {
      final folderLower = d.path.split(p.separator).last.toLowerCase();
      // Use whole word matching for folder names too
      final folderWords = folderLower.replaceAll(RegExp(r"[^a-z0-9\s]"), ' ').split(' ').toSet();
      return gameWords.any((word) => folderWords.contains(word));
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
    final saveRoot = await _getRpcs3SaveRoot(platformSlug: game.platformSlug);
    final dirs = await _findSaveDirs(saveRoot, game);
    return dirs.isNotEmpty ? dirs.first.path : null;
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveRoot = await _getRpcs3SaveRoot(platformSlug: game.platformSlug);

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
      final saveRoot = await _getRpcs3SaveRoot(platformSlug: game.platformSlug);

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        
        // Ensure the leaf directory exists
        await io.Directory(saveRoot).create(recursive: true);

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
      debugPrint('[RPCS3] Restore error: $e');
      rethrow;
    }
    }
    }