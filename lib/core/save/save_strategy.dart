import 'dart:io' as io;
import 'dart:typed_data';
import 'package:path/path.dart' as p;

import '../platform/platform_info.dart';
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

  /// Strips region/version tags from [name] and collapses whitespace, so it can
  /// be substring-matched against emulator save filenames (which use the bare
  /// game title, e.g. DuckStation's "Suikoden II_1.mcd").
  ///
  /// Multi-disc ROMs exposed via RomM are `.m3u` playlists whose filename
  /// carries tags the save files don't have, e.g. "Final Fantasy VII (USA).m3u"
  /// → "Final Fantasy VII_1.mcd". Without stripping `(USA)`, the save card
  /// never matches and pushes/pulls silently do nothing (issue #62).
  String normalizeSaveMatchName(String name) {
    var cleaned = name
        .replaceAll(RegExp(r'\([^)]*\)'), '') // region/version (USA) (Rev 1)
        .replaceAll(RegExp(r'\[[^\]]*\]'), '') // [!] [b] [T+Eng]
        .replaceAll(RegExp(r'[\s._-]+$'), '') // trailing dots/dashes/underscores
        .replaceAll(RegExp(r'\s+'), ' ') // collapse spaces
        .trim();
    return cleaned.isEmpty ? name : cleaned;
  }

  // ─── Shared helper: RetroArch config lookup ──────────────────────────────

  /// Reads `savefile_directory` and sort flags from retroarch.cfg for platforms
  /// where RetroArch manages saves via a core subfolder (e.g. mGBA, MelonDS).
  ///
  /// Returns the full path to the core-specific subfolder (e.g.
  /// `/Users/xyz/Documents/RetroArch/saves/mGBA`) when `sort_savefiles_enable`
  /// is true (the default), or the flat save directory when it is false.
  /// Returns `null` if the config is not found.
  static Future<String?> retroarchCoreSaveDir(DirectoryService directoryService, String coreSaveFolder, {PlatformInfo? platform}) async {
    final p_ = platform ?? PlatformInfo.current;
    final List<String> configCandidates = [];

    if (p_.isMacOS) {
      final home = p_.environment['HOME'] ?? '';
      configCandidates.add(p.join(home, 'Library', 'Application Support', 'RetroArch', 'config', 'retroarch.cfg'));
      configCandidates.add(p.join(home, '.config', 'retroarch', 'retroarch.cfg'));
    } else if (p_.isLinux) {
      final home = p_.environment['HOME'] ?? '';
      configCandidates.add(p.join(home, '.config', 'retroarch', 'retroarch.cfg'));
    } else if (p_.isWindows) {
      final appData = p_.environment['APPDATA'] ?? '';
      configCandidates.add(p.join(appData, 'RetroArch', 'retroarch.cfg'));
    }

    final exePath = await directoryService.findEmulatorExecutable('retroarch', _retroarchExe(platform: p_));
    if (exePath != null) {
      String exeDir = p_.isMacOS
          ? p.join(io.File(exePath).parent.parent.parent.parent.path)
          : io.File(exePath).parent.path;
      if (await io.FileSystemEntity.isDirectory(exePath)) exeDir = exePath;
      configCandidates.add(p.join(exeDir, 'retroarch.cfg'));
    }

    final savefileDirRe = RegExp(r'^\s*savefile_directory\s*=\s*"([^"]*)"');
    final sortRe = RegExp(r'^\s*sort_savefiles_enable\s*=\s*"?(true|false)"?');

    for (final cfgPath in configCandidates) {
      final cfgFile = io.File(cfgPath);
      if (!await cfgFile.exists()) continue;
      try {
        final lines = await cfgFile.readAsLines();
        String? saveDir;
        bool sortSavefiles = true; // RetroArch default
        for (final line in lines) {
          final match = savefileDirRe.firstMatch(line);
          if (match != null) {
            var dir = match.group(1)!;
            if (dir.startsWith('~')) {
              final home = p_.environment['HOME'];
              if (home != null) dir = dir.replaceFirst('~', home);
            }
            if (await io.Directory(dir).exists()) {
              saveDir = dir;
            }
          }
          final sortMatch = sortRe.firstMatch(line);
          if (sortMatch != null) {
            sortSavefiles = sortMatch.group(1)!.toLowerCase() == 'true';
          }
        }
        if (saveDir != null) {
          if (!sortSavefiles) {
            // sort_savefiles_enable=false: saves are flat, no core subfolder
            return saveDir;
          }
          final coreDir = p.join(saveDir, coreSaveFolder);
          if (await io.Directory(coreDir).exists()) {
            return coreDir;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static String _retroarchExe({PlatformInfo? platform}) {
    final p_ = platform ?? PlatformInfo.current;
    if (p_.isWindows) return 'RetroArch.exe';
    if (p_.isMacOS) return 'RetroArch.app/Contents/MacOS/RetroArch';
    return 'retroarch';
  }
}
