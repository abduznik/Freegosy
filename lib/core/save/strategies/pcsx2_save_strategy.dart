import 'dart:io' as io;
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for PCSX2 (PlayStation 2).
/// Memcards: {systemDir}/memcards/*.ps2
/// States:   {systemDir}/sstates/{stem}.*.
class Pcsx2SaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  Pcsx2SaveStrategy(this._directoryService);

  @override
  String get strategyId => 'pcsx2';

  Future<String> _getSaveRoot() async {
    // 1. Check portable mode first — exe next to memcards folder
    final exePath = await _directoryService.findEmulatorExecutable('pcsx2', 'pcsx2-qt.exe');
    if (exePath != null) {
      String exeDir = io.File(exePath).parent.path;
      if (await io.FileSystemEntity.isDirectory(exePath)) {
        exeDir = exePath;
      }
      final portableMemcards = p.join(exeDir, 'memcards');
      if (await io.Directory(portableMemcards).exists()) {
        return exeDir;
      }
    }

    // 2. Fall back to app support directory
    final resolvedPath = await _directoryService.getEmulatorSystemDirectory('pcsx2');
    if (!await io.Directory(resolvedPath).exists()) {
      throw Exception('Save directory not found for PCSX2 at $resolvedPath. Please launch PCSX2 at least once to generate save data.');
    }
    return resolvedPath;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final root = await _getSaveRoot();
    return p.join(root, 'memcards');
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final root = await _getSaveRoot();

    final result = <io.File>[];

    // Memory cards — scan all .ps2 files in memcards folder
    // Note: This matches the existing behavior of syncing entire cards.
    final memcardsDir = io.Directory(p.join(root, 'memcards'));
    if (await memcardsDir.exists()) {
      await for (final entity in memcardsDir.list()) {
        if (entity is! io.File) continue;
        final basename = p.basename(entity.path);
        if (!basename.toLowerCase().endsWith('.ps2')) continue;
        // Skip timestamped backup copies like "Mcd001 [2026-03-26_09-18-21].ps2"
        if (basename.contains('[') || basename.contains(']')) continue;
        if (sessionStart != null) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(sessionStart)) continue;
        }
        result.add(entity);
      }
    }

    // Save states — named after ROM stem
    final stem = getRomStem(game);
    final statesDir = io.Directory(p.join(root, 'sstates'));
    if (await statesDir.exists()) {
      await for (final entity in statesDir.list()) {
        if (entity is! io.File) continue;
        if (!p.basename(entity.path).contains(stem)) continue;
        if (sessionStart != null) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(sessionStart)) continue;
        }
        result.add(entity);
      }
    }

    return result;
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final root = await _getSaveRoot();

      // Cloud saves come as zips — extract into the appropriate directory
      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          // Determine target dir by file extension
          final entryLower = entry.name.toLowerCase();
          final targetDir = entryLower.endsWith('.ps2')
              ? p.join(root, 'memcards')
              : p.join(root, 'sstates');

          if (entry.isFile) {
            final targetPath = p.join(targetDir, entry.name);
            await backupSave(targetPath);
            final outFile = io.File(targetPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          }
        }
        return true;
      }

      // Single file fallback
      final isState = filename.contains('.') &&
          int.tryParse(filename.split('.').last) != null;
      final targetDir = isState ? p.join(root, 'sstates') : p.join(root, 'memcards');
      await io.Directory(targetDir).create(recursive: true);
      final targetPath = p.join(targetDir, filename);
      await backupSave(targetPath);
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}