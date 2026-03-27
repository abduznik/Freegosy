import 'dart:io';
import 'dart:typed_data';

import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for Dolphin emulator (GameCube / Wii).
///
/// Save files live in {emulatorDir}/User/GC/{region}/Card A/
class DolphinSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  DolphinSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'dolphin';

  /// Detects region code from [romPath].
  String _detectRegion(String romPath) {
    final upper = romPath.toUpperCase();
    if (upper.contains('EUR') || upper.contains('PAL')) return 'EUR';
    if (upper.contains('JAP') || upper.contains('JPN')) return 'JAP';
    return 'USA';
  }

  /// Normalizes game name for comparison.
  String _normalizeGameName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable('dolphin', 'Dolphin.exe');
    if (exePath == null) return null;

    final emulatorDir = File(exePath).parent.path;
    final region = _detectRegion(romPath);
    return '$emulatorDir/User/GC/$region/Card A';
  }

  @override
  Future<List<File>> getSaveFiles(
      Game game,
      String romPath,
      {DateTime? sessionStart,
      String syncMode = 'both'}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];

    final dir = Directory(saveDir);
    if (!await dir.exists()) return [];

    // First pass: collect all GCI files and read their
    // game codes from binary headers
    final allGciFiles = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final filename = entity.path
          .split(RegExp(r'[/\\]'))
          .last
          .toUpperCase();
      if (!filename.endsWith('.GCI')) continue;
      allGciFiles.add(entity);
    }

    // Read game codes from all GCI headers to find which
    // code belongs to our target game.
    // We find the game code by matching GCI filename
    // against the game name from RomM.
    // GCI filename format: XX-GAMECODE-GAME NAME.gci
    // Extract the game code (segment between first and
    // second dash) from filename.

    String? targetGameCode;
    final normalizedTarget = _normalizeGameName(game.displayName);

    for (final gciFile in allGciFiles) {
      final filename = gciFile.path
          .split(RegExp(r'[/\\]'))
          .last;
      final parts = filename.split('-');
      if (parts.length < 3) continue;
      final codeFromFilename = parts[1].toUpperCase();
      // Get the name part (everything after second dash,
      // before the bracket timestamp)
      final namePart = parts.sublist(2).join('-')
          .replaceAll(RegExp(r'\[.*?\]'), '')
          .trim();
      final normalizedGciName = _normalizeGameName(namePart);

      if (normalizedGciName.contains(normalizedTarget) ||
          normalizedTarget.contains(normalizedGciName)) {
        targetGameCode = codeFromFilename;
        break;
      }
    }

    // If we found a matching game code filter by it,
    // otherwise return empty list to avoid syncing
    // wrong game saves
    if (targetGameCode == null) {
      return [];
    }

    final result = <File>[];
    for (final gciFile in allGciFiles) {
      final filename = gciFile.path
          .split(RegExp(r'[/\\]'))
          .last;
      final parts = filename.split('-');
      if (parts.length < 2) continue;
      final codeFromFilename = parts[1].toUpperCase();

      if (codeFromFilename != targetGameCode) continue;

      if (sessionStart != null) {
        final stat = await gciFile.stat();
        if (stat.modified.isBefore(sessionStart)) continue;
      }
      result.add(gciFile);
    }

    return result;
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) return false;

      final dir = Directory(saveDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final targetPath = '$saveDir/$filename';
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}
