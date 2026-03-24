import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for PCSX2 (PlayStation 2).
/// Memcards: {emulatorDir}/memcards/Mcd001.ps2, Mcd002.ps2
/// States:   {emulatorDir}/sstates/{stem}.000 etc.
class Pcsx2SaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  Pcsx2SaveStrategy(this._directoryService);

  @override
  String get strategyId => 'pcsx2';

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable(
        'pcsx2', 'pcsx2-qt.exe');
    if (exePath == null) return null;
    return '${File(exePath).parent.path}/memcards';
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final exePath = await _directoryService.findEmulatorExecutable(
        'pcsx2', 'pcsx2-qt.exe');
    if (exePath == null) return [];
    final exeDir = File(exePath).parent.path;

    final candidates = <File>[];

    // Memory cards — shared across all PS2 games
    if (syncMode == 'saves' || syncMode == 'both') {
      candidates.add(File('$exeDir/memcards/Mcd001.ps2'));
      candidates.add(File('$exeDir/memcards/Mcd002.ps2'));
    }

    // Save states — named after ROM stem
    if (syncMode == 'states' || syncMode == 'both') {
      final stem = getRomStem(game);
      final statesDir = '$exeDir/sstates';
      for (int i = 0; i <= 9; i++) {
        candidates.add(File('$statesDir/$stem.${'$i'.padLeft(3, '0')}'));
      }
    }

    final result = <File>[];
    for (final f in candidates) {
      if (!await f.exists()) continue;
      if (sessionStart != null) {
        final stat = await f.stat();
        if (stat.modified.isBefore(sessionStart)) continue;
      }
      result.add(f);
    }
    return result;
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final exePath = await _directoryService.findEmulatorExecutable(
          'pcsx2', 'pcsx2-qt.exe');
      if (exePath == null) return false;
      final exeDir = File(exePath).parent.path;

      final isState = filename.contains('.') &&
          int.tryParse(filename.split('.').last) != null;
      final targetDir = isState ? '$exeDir/sstates' : '$exeDir/memcards';

      final dir = Directory(targetDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final targetPath = '$targetDir/$filename';
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      debugPrint('[Pcsx2SaveStrategy] restored $filename to $targetPath');
      return true;
    } catch (e) {
      debugPrint('[Pcsx2SaveStrategy] restoreSave error: $e');
      return false;
    }
  }
}