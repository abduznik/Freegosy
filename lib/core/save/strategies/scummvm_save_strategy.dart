import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for ScummVM.
///
/// ScummVM names its save files after the game's target id and keeps every
/// game's saves together, so telling one RomM game's saves apart would mean
/// reading ScummVM's own config. Instead Freegosy starts ScummVM with
/// `--savepath` pointing at a folder of its own for each game
/// ([saveDirFor]); that whole folder is the game's save and syncs as one.
class ScummVMSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  ScummVMSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'scummvm';

  @override
  bool get supportsSaveSync => true;

  /// The folder ScummVM is told to save [game] in.
  static Future<String> saveDirFor(DirectoryService directoryService, Game game) async {
    final base = await directoryService.getEmulatorAppSupportDirectory('scummvm');
    return p.join(base, 'freegosy_saves', game.id);
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) => saveDirFor(_directoryService, game);

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final dir = Directory((await getSaveDir(game, romPath))!);
    if (!await dir.exists()) return [];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File || entity.path.contains('.bak')) continue;
      if (sessionStart != null) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
      }
      // The folder itself stands for the save: sync zips it as a whole.
      return [File(dir.path)];
    }
    return [];
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, data, String filename) async {
    try {
      final saveDir = (await getSaveDir(game, destPath))!;
      await Directory(saveDir).create(recursive: true);
      if (!filename.toLowerCase().endsWith('.zip')) return false;
      for (final entry in ZipDecoder().decodeBytes(data)) {
        if (entry.name == 'freegosy_sync.txt' || entry.name.contains('.bak')) continue;
        final target = p.normalize(p.join(saveDir, entry.name));
        // Never write outside the game's save folder.
        if (!p.isWithin(saveDir, target)) continue;
        if (entry.isFile) {
          await backupSave(target);
          await File(target).parent.create(recursive: true);
          await File(target).writeAsBytes(entry.content as List<int>);
        } else {
          await Directory(target).create(recursive: true);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
