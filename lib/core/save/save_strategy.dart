import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

import '../romm/romm_models.dart';

// ─── Exceptions ──────────────────────────────────────────────────────────────

class SaveMappingRequiredException implements Exception {
  final String message;
  SaveMappingRequiredException([this.message = 'Manual save mapping required']);
  @override
  String toString() => 'SaveMappingRequiredException: $message';
}

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

  /// Returns all save files associated with [game], optionally paired with screenshots.
  /// If [sessionStart] is provided, only files modified after that time are returned.
  Future<Map<File, File?>> getSaveFilesWithScreenshots(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final files = await getSaveFiles(game, romPath, sessionStart: sessionStart, syncMode: syncMode);
    return {for (var f in files) f: null};
  }

  /// Restores save [data] named [filename] for [game] at [destPath].
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename);

  // ─── Shared helper: rotation backup ──────────────────────────────────────

  /// Creates a .bak rotation (up to 3 versions) for the file at [path].
  Future<void> backupSave(String path) async {
    final normalized = p.normalize(path);
    final file = File(normalized);
    if (!await file.exists()) return;
    try {
      final bak2 = File('$normalized.bak2');
      final bak1 = File('$normalized.bak1');
      final bak = File('$normalized.bak');
      if (await bak2.exists()) await bak2.delete();
      if (await bak1.exists()) await bak1.rename('$normalized.bak2');
      if (await bak.exists()) await bak.rename('$normalized.bak1');
      await file.copy('$normalized.bak');
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
