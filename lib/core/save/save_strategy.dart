import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:archive/archive.dart';
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

/// Thrown by save sync when the emulator is set up so that its saves can't be
/// synced for one game (see [SaveStrategy.saveSyncBlockedReason]). [message]
/// tells the user why and what to change; it is not an error to retry.
class SaveSyncNotPossibleException implements Exception {
  final String message;
  SaveSyncNotPossibleException(this.message);
  @override
  String toString() => 'SaveSyncNotPossibleException: $message';
}

/// A [SaveSyncNotPossibleException] for how the emulator is set up (see
/// [SaveStrategy.saveSyncBlockedReason]), as opposed to a problem with one
/// save. It holds for every launch until the settings change, so the
/// pre-launch pull only logs it.
class SaveSyncBlockedException extends SaveSyncNotPossibleException {
  SaveSyncBlockedException(super.message);
}

/// Tells a pull that started before a launch whether the launch went ahead
/// without it (the pre-launch wait timed out). A save written after the
/// emulator has opened its files would be overwritten from memory when the
/// game next saves, so a late pull doesn't write it.
///
/// [run] makes the guard [current] for everything [body] starts, so the
/// check reaches the save strategies without passing it through every call.
class SaveRestoreGuard {
  static const _zoneKey = #freegosySaveRestoreGuard;

  bool _tooLate = false;

  /// The launch went ahead: the pull must not write anything any more.
  void markTooLate() => _tooLate = true;

  bool get tooLate => _tooLate;

  T run<T>(T Function() body) => runZoned(body, zoneValues: {_zoneKey: this});

  static SaveRestoreGuard? get current => Zone.current[_zoneKey] as SaveRestoreGuard?;

  /// Whether the pull running here was overtaken by the launch.
  static bool get restoreTooLate => current?.tooLate ?? false;
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

  /// Why [game]'s saves can't be synced with the emulator set up as it is
  /// (e.g. no memory card at all), or null when they can.
  /// Checked before every push and pull; a reason stops both and reaches the
  /// user. Local backups are not affected. Must not throw: a failure to tell
  /// means null.
  Future<String?> saveSyncBlockedReason(Game game, String romPath) async => null;

  /// Whether the pre-launch pull must finish before the emulator starts,
  /// e.g. because restoring changes a file other games' saves share. The
  /// pull otherwise runs alongside the launch.
  Future<bool> pullMustFinishBeforeLaunch(Game game, String romPath) async => false;

  /// Puts a local backup back: [zipBytes] is a zip of getSaveFiles, as
  /// BackupService makes it. Save files other games share (memory cards,
  /// see pullMustFinishBeforeLaunch) go back one by one through restoreSave,
  /// like a pulled card, which takes only this game's saves from each.
  /// Anything else is unzipped into getSaveDir; nothing outside it.
  Future<bool> restoreBackup(Game game, String romPath, Uint8List zipBytes, String zipName) async {
    if (await pullMustFinishBeforeLaunch(game, romPath)) {
      var ok = true;
      for (final entry in ZipDecoder().decodeBytes(zipBytes)) {
        if (!entry.isFile) continue;
        final bytes = Uint8List.fromList(entry.content as List<int>);
        ok = await restoreSave(game, romPath, bytes, p.basename(entry.name)) && ok;
      }
      return ok;
    }
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return false;
    for (final entry in ZipDecoder().decodeBytes(zipBytes)) {
      final path = p.normalize(p.join(saveDir, entry.name));
      if (!p.isWithin(saveDir, path)) continue;
      if (entry.isFile) {
        await io.File(path).parent.create(recursive: true);
        await io.File(path).writeAsBytes(entry.content as List<int>);
      } else {
        await io.Directory(path).create(recursive: true);
      }
    }
    return true;
  }

  /// Returns the local save directory for [game] given its [romPath].
  Future<String?> getSaveDir(Game game, String romPath);

  /// Returns all save files associated with [game]: what local backups keep
  /// (BackupService). If [sessionStart] is provided, only files modified
  /// after that time are returned.
  Future<List<io.File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'});

  /// Returns all save files associated with [game], optionally paired with screenshots:
  /// what save sync uploads and compares (SaveSyncService). By default the
  /// same files as [getSaveFiles]; a strategy may upload something narrower
  /// than it backs up (e.g. one game's saves out of a card shared by all).
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
  /// Whether [fileName] is a `.sav`/`.srm` for exactly one of [stems] (ROM
  /// names, no extension). RomM's web player adds a ` [timestamp]` suffix,
  /// which is ignored. Partial/word matches are deliberately not accepted: a
  /// shared title word would pick another game's save.
  static bool saveNameMatchesRom(String fileName, Iterable<String> stems) {
    final lower = fileName.toLowerCase();
    if (!lower.endsWith('.sav') && !lower.endsWith('.srm')) return false;
    final base = lower.substring(0, lower.length - 4).replaceFirst(RegExp(r'\s*\[[^\]]*\]$'), '');
    return stems.any((s) => s.toLowerCase() == base);
  }

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
