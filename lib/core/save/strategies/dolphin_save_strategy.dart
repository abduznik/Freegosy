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

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final exePath = await _directoryService.findEmulatorExecutable('dolphin', 'Dolphin.exe');
    if (exePath == null) return null;

    final emulatorDir = File(exePath).parent.path;
    final region = _detectRegion(romPath);
    return '$emulatorDir/User/GC/$region/Card A';
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];

    final dir = Directory(saveDir);
    if (!await dir.exists()) return [];

    final result = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.gci')) continue;
      if (sessionStart != null) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(sessionStart)) continue;
      }
      result.add(entity);
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
      print('[DolphinSaveStrategy] restored $filename to $targetPath');
      return true;
    } catch (e) {
      print('[DolphinSaveStrategy] restoreSave error: $e');
      return false;
    }
  }
}
