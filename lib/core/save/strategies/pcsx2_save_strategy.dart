import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for PCSX2 (PlayStation 2).
/// Memcards: {emulatorDir}\memcards\*.ps2
/// States:   {emulatorDir}\sstates\{stem}.*.
class Pcsx2SaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  Pcsx2SaveStrategy(this._directoryService);

  @override
  String get strategyId => 'pcsx2';

  Future<String?> _getExeDir() async {
    final exePath = await _directoryService.findEmulatorExecutable(
        'pcsx2', 'pcsx2-qt.exe');
    if (exePath == null) return null;
    return File(exePath).parent.path.replaceAll('/', '\\');
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final exeDir = await _getExeDir();
    if (exeDir == null) return null;
    return '$exeDir\\memcards';
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final exeDir = await _getExeDir();
    if (exeDir == null) return [];

    final result = <File>[];

    // Memory cards — scan all .ps2 files in memcards folder
    final memcardsDir = Directory('$exeDir\\memcards');
    if (await memcardsDir.exists()) {
      await for (final entity in memcardsDir.list()) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.ps2')) continue;
        if (sessionStart != null) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(sessionStart)) continue;
        }
        result.add(entity);
      }
    }

    // Save states — named after ROM stem
    final stem = getRomStem(game);
    final statesDir = Directory('$exeDir\\sstates');
    if (await statesDir.exists()) {
      await for (final entity in statesDir.list()) {
        if (entity is! File) continue;
        if (!entity.path.contains(stem)) continue;
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
      final exeDir = await _getExeDir();
      if (exeDir == null) return false;

      // Cloud saves come as zips — extract into the appropriate directory
      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          // Determine target dir by file extension
          final entryLower = entry.name.toLowerCase();
          final targetDir = entryLower.endsWith('.ps2')
              ? '$exeDir\\memcards'
              : '$exeDir\\sstates';

          if (entry.isFile) {
            final targetPath = '$targetDir\\${entry.name}';
            await backupSave(targetPath);
            final outFile = File(targetPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          }
        }
        return true;
      }

      // Single file fallback
      final isState = filename.contains('.') &&
          int.tryParse(filename.split('.').last) != null;
      final targetDir = isState ? '$exeDir\\sstates' : '$exeDir\\memcards';
      await Directory(targetDir).create(recursive: true);
      final targetPath = '$targetDir\\$filename';
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}