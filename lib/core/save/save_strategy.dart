import 'dart:io' as io;
import 'dart:typed_data';
import 'package:path/path.dart' as p;

import '../storage/directory_service.dart';
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

  /// Whether this strategy prefers to upload/download saves as zipped archives.
  /// Strategies that return false will upload the raw save file directly,
  /// which is needed for emulators like emulator.js in RomM to read the files (e.g. .srm, .sav).
  bool get shouldZip => true;

  /// Returns the local save directory for [game] given its [romPath].
  Future<String?> getSaveDir(Game game, String romPath);

  /// Returns all save files associated with [game].
  /// If [sessionStart] is provided, only files modified after that time are returned.
  Future<List<io.File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'});

  /// Returns all save files associated with [game], optionally paired with screenshots.
  /// If [sessionStart] is provided, only files modified after that time are returned.
  Future<Map<io.File, io.File?>> getSaveFilesWithScreenshots(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final files = await getSaveFiles(game, romPath, sessionStart: sessionStart, syncMode: syncMode);
    return {for (var f in files) f: null};
  }

  /// Restores save [data] named [filename] for [game] at [destPath].
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename);

  // ─── Shared helper: rotation backup ──────────────────────────────────────

  /// Creates a .bak rotation (up to 3 versions) for the file at [path].
  Future<void> backupSave(String path) async {
    final normalized = p.normalize(path);
    final file = io.File(normalized);
    if (!await file.exists()) return;
    try {
      final bak2 = io.File('$normalized.bak2');
      final bak1 = io.File('$normalized.bak1');
      final bak = io.File('$normalized.bak');
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

  // ─── Shared helper: RetroArch config lookup ──────────────────────────────

  /// Reads `savefile_directory` from retroarch.cfg for platforms where RetroArch
  /// manages saves via a core subfolder (e.g. mGBA, MelonDS, Dolphin).
  ///
  /// Returns the full path to the core-specific subfolder (e.g.
  /// `/Users/xyz/Documents/RetroArch/saves/mGBA`), or `null` if the config
  /// is not found or the core folder does not exist.
  static Future<String?> retroarchCoreSaveDir(DirectoryService directoryService, String coreSaveFolder) async {
    final List<String> configCandidates = [];

    if (io.Platform.isMacOS) {
      final home = io.Platform.environment['HOME'] ?? '';
      configCandidates.add(p.join(home, 'Library', 'Application Support', 'RetroArch', 'config', 'retroarch.cfg'));
      configCandidates.add(p.join(home, '.config', 'retroarch', 'retroarch.cfg'));
    } else if (io.Platform.isLinux) {
      final home = io.Platform.environment['HOME'] ?? '';
      configCandidates.add(p.join(home, '.config', 'retroarch', 'retroarch.cfg'));
    } else if (io.Platform.isWindows) {
      final appData = io.Platform.environment['APPDATA'] ?? '';
      configCandidates.add(p.join(appData, 'RetroArch', 'retroarch.cfg'));
    }

    final exePath = await directoryService.findEmulatorExecutable('retroarch', _retroarchExe());
    if (exePath != null) {
      String exeDir = io.Platform.isMacOS
          ? p.join(io.File(exePath).parent.parent.parent.parent.path)
          : io.File(exePath).parent.path;
      if (await io.FileSystemEntity.isDirectory(exePath)) exeDir = exePath;
      configCandidates.add(p.join(exeDir, 'retroarch.cfg'));
    }

    for (final cfgPath in configCandidates) {
      final cfgFile = io.File(cfgPath);
      if (!await cfgFile.exists()) continue;
      try {
        final lines = await cfgFile.readAsLines();
        for (final line in lines) {
          final match = RegExp(r'^\s*savefile_directory\s*=\s*"([^"]*)"').firstMatch(line);
          if (match != null) {
            var dir = match.group(1)!;
            if (dir.startsWith('~')) {
              final home = io.Platform.environment['HOME'];
              if (home != null) dir = dir.replaceFirst('~', home);
            }
            if (await io.Directory(dir).exists()) {
              final coreDir = p.join(dir, coreSaveFolder);
              if (await io.Directory(coreDir).exists()) {
                return coreDir;
              }
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static String _retroarchExe() {
    if (io.Platform.isWindows) return 'RetroArch.exe';
    if (io.Platform.isMacOS) return 'RetroArch.app/Contents/MacOS/RetroArch';
    return 'retroarch';
  }
}
