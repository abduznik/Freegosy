import 'dart:io';
import 'dart:typed_data';

import '../romm/romm_models.dart';

/// Abstract base for all save-file strategies.
abstract class SaveStrategy {
  String get strategyId;
  
  /// Whether this strategy supports save synchronization.
  bool get supportsSaveSync => false;

  /// Returns the local save directory for [game] given its [romPath].
  Future<String?> getSaveDir(Game game, String romPath);

  /// Returns all save files associated with [game].
  /// If [sessionStart] is provided, only files modified after that time are returned.
  Future<List<File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'});

  /// Restores save [data] named [filename] for [game] at [destPath].
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename);

  // ─── Shared helper: rotation backup ──────────────────────────────────────

  /// Creates a .bak rotation (up to 3 versions) for the file at [path].
  Future<void> backupSave(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    try {
      final bak2 = File('$path.bak2');
      final bak1 = File('$path.bak1');
      final bak = File('$path.bak');
      if (await bak2.exists()) await bak2.delete();
      if (await bak1.exists()) await bak1.rename('$path.bak2');
      if (await bak.exists()) await bak.rename('$path.bak1');
      await file.copy('$path.bak');
    } catch (e) {
      // silent
    }
  }

  // ─── Shared helper: ROM stem ──────────────────────────────────────────────

  /// Returns the base filename (without extension) used to identify save files.
  String getRomStem(Game game) {
    final name = game.fsName ?? game.name;
    final dot = name.lastIndexOf('.');
    if (dot > 0) return name.substring(0, dot);
    return name;
  }
}
