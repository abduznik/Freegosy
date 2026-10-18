import 'dart:io';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../platform/platform_info.dart';
import '../../romm/romm_models.dart';
import '../../storage/app_preferences.dart';
import '../../windows/windows_known_folders.dart';
import '../../windows/pcgamingwiki_service.dart';
import '../save_strategy.dart';
import 'package:dio/dio.dart';

class WindowsSaveStrategy extends SaveStrategy {
  final PcGamingWikiService _wikiService;
  final AppPreferences _prefs;
  final PlatformInfo _platform;

  /// The Wine/Proton prefix a game runs in (Linux), or null when it has none yet.
  final Future<String?> Function(Game game)? _prefixDirFor;

  // Manual override paths set by user per game id
  final Map<String, String> _manualOverrides = {};
  // Saved PCGW path
  final Map<String, String> _pcGamingWikiSavePath = {};

  // Save file filter patterns per game id (comma-separated: "*.ini, *.bin, eeprom.*")
  final Map<String, String> _saveFilters = {};
  // Same, but for file filters retrieved from PCGamingWiki
  final Map<String, String> _wikiSaveFilters = {};

  WindowsSaveStrategy(this._prefs, {PlatformInfo? platform, Future<String?> Function(Game game)? prefixDirFor, PcGamingWikiService? wikiService})
      : _platform = platform ?? PlatformInfo.current,
        _prefixDirFor = prefixDirFor,
        _wikiService = wikiService ?? PcGamingWikiService(Dio(), platform: platform);

  /// Windows' well-known folders for [game] on this computer: the environment on Windows, the game's
  /// Wine/Proton prefix on Linux.
  Future<WindowsKnownFolders> knownFolders(Game game) async {
    if (_platform.isWindows) return WindowsKnownFolders.forPlatform(_platform);
    final prefix = await _prefixDirFor?.call(game);
    return WindowsKnownFolders.forPlatform(_platform, prefixDir: prefix != null && Directory(prefix).existsSync() ? prefix : null);
  }

  static String _gameDirOf(String romPath) => Directory(romPath).existsSync() ? romPath : File(romPath).parent.path;

  /// [absolute] as stored in a synced save's metadata: relative to a Windows folder, so another computer
  /// (Windows, or Linux with its own prefix) can put it back in the matching place.
  Future<String> toPortablePath(Game game, String romPath, String absolute) async =>
      (await knownFolders(game)).toPortable(absolute, gameDir: _gameDirOf(romPath));

  /// The local path a stored [portable] save path stands for here.
  Future<String> fromPortablePath(Game game, String destPath, String portable) async =>
      (await knownFolders(game)).fromPortable(portable, gameDir: _gameDirOf(destPath), posix: !_platform.isWindows);

  @override
  String get strategyId => 'windows';

  /// Allows the user to manually set a save path for a game.
  static const String _prefsPrefix = 'win_save_';
  /// Allows PCGamingWiki offline serialization for the save path for a game.
  static const String _pcGamingWikiPrefsPrefix = 'win_pcGamingWikiSavePath_';

  void loadPersistedOverrides() {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefsPrefix));
    for (final key in keys) {
      final gameId = key.substring(_prefsPrefix.length);
      final path = _prefs.getString(key);
      if (path != null && path.isNotEmpty) _manualOverrides[gameId] = path;
    }
  }

  void loadPersistedPcGamingWikiSavePath() {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_pcGamingWikiPrefsPrefix));
    for (final key in keys) {
      final gameId = key.substring(_pcGamingWikiPrefsPrefix.length);
      final path = _prefs.getString(key);
      if (path != null && path.isNotEmpty) _pcGamingWikiSavePath[gameId] = path;
    }
  }

  /// Allows the user to manually set a save path for a game.
  Future<void> setManualOverride(String gameId, String path) async {
    _manualOverrides[gameId] = path;
    await _prefs.setString('$_prefsPrefix$gameId', path);
  }

 // Enables saving the resolved Save Path initially retrieved with PCGW 
  Future<void> setPcGamingWikiSavePath(String gameId, String path) async {
    _pcGamingWikiSavePath[gameId] = path;
    await _prefs.setString('$_pcGamingWikiPrefsPrefix$gameId', path);
  }

  String? getManualOverride(String gameId) => _manualOverrides[gameId];
  String? getPcGamingWikiSavePath(String gameId) => _pcGamingWikiSavePath[gameId];

  static const String _filterPrefix = 'win_filter_';
  static const String _wikiFilterPrefix = 'win_wikiFilter_';

  void loadPersistedFilters() {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_filterPrefix));
    for (final key in keys) {
      final gameId = key.substring(_filterPrefix.length);
      final filter = _prefs.getString(key);
      if (filter != null) _saveFilters[gameId] = filter;
    }
  }

  void loadPersistedWikiFilters() {
  final keys = _prefs.getKeys().where((k) => k.startsWith(_wikiFilterPrefix));
  for (final key in keys) {
    final gameId = key.substring(_wikiFilterPrefix.length);
    final filter = _prefs.getString(key);
    if (filter != null) _wikiSaveFilters[gameId] = filter;
  }
}

  Future<void> setSaveFilter(String gameId, String filter) async {
    _saveFilters[gameId] = filter;
    await _prefs.setString('$_filterPrefix$gameId', filter);
  }

  Future<void> setWikiSaveFilter(String gameId, String filter) async {
    _wikiSaveFilters[gameId] = filter;
    await _prefs.setString('$_wikiFilterPrefix$gameId', filter);
  }

  String? getSaveFilter(String gameId) => _saveFilters[gameId];
  String? getWikiSaveFilter(String gameId) => _wikiSaveFilters[gameId];

  @override
  Future<String?> getSaveDir(Game game, String romPath, {String? metadataSavePath}) async {
    // Manual override takes priority
    final manual = _manualOverrides[game.id];
    if (manual != null && manual.isNotEmpty) {
      debugPrint('[WindowsSave] Using manual override for ${game.name}: $manual');
      return manual;
    }    

    // Determine the game directory
    final isDir = await Directory(romPath).exists();
    final gameDir = isDir ? romPath : File(romPath).parent.path;

    //If a "freegosy_sync.txt" file has been found AND 
    //contains a cached save path with env vars, let's retrieve it
    if (metadataSavePath != null)
    {
      debugPrint('[WindowsSave] Using save path found in freegosy_sync.txt for ${game.name}: $metadataSavePath');
      return metadataSavePath;
    }

    // Check if prefs already have the PCGamingWiki save path registered
    final pcgw = _pcGamingWikiSavePath[game.id];
    if (pcgw != null && pcgw.isNotEmpty) {
      debugPrint('[WindowsSave] Using cached PCGamingWiki save path for ${game.name}: $pcgw');
      return pcgw;
    }

    // Try Searching PCGamingWiki
    try {
      debugPrint('[WindowsSave] Querying PCGamingWiki for ${game.name}...');
      final locations = await _wikiService.getSaveLocations(game.name, gameDir: gameDir, folders: await knownFolders(game));
      if (locations.isNotEmpty) {
        debugPrint('[WindowsSave] PCGamingWiki found ${locations.length} save location(s):');
        for (final loc in locations) {
          debugPrint('[WindowsSave]   raw: ${loc['raw']} → path: ${loc['path']}');
        }
        final resolved = locations.first['path'];
        var resolvedFileFilter = RegExp(r'\.[a-zA-Z0-9]{2,4}$').hasMatch(locations.first['raw']!) ? locations.first['raw']?.split('\\').last : '';
        // PCGW Pages sometimes describes wild cards as "file*.ext", we need to change it into "*.ext"
        if (resolvedFileFilter!.contains('file*')) resolvedFileFilter = resolvedFileFilter.replaceFirst('file*', '*');
        if (resolved != null) {
          final dir = Directory(resolved);
          if (await dir.exists()) {
            // Check if this directory actually has save files
            if (await _hasSaveFiles(dir)) {
              debugPrint('[WindowsSave] PCGamingWiki dir has save files: $resolved');
              setPcGamingWikiSavePath(game.id, resolved);
              if (resolvedFileFilter.isNotEmpty) setWikiSaveFilter(game.id, resolvedFileFilter);
              return resolved;
            }
            debugPrint('[WindowsSave] PCGamingWiki dir exists but is empty: $resolved');
          } else {
            // Try to create it
            try {
              await dir.create(recursive: true);
              debugPrint('[WindowsSave] Created PCGamingWiki dir: $resolved');
            } catch (e) {
              debugPrint('[WindowsSave] Failed to create dir: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[WindowsSave] PCGamingWiki lookup failed: $e');
    }

    // Search recursively for a Save folder that actually contains files
    final found = await _findSaveFolderRecursive(gameDir);
    if (found != null) {
      debugPrint('[WindowsSave] Found Save folder with files: $found');
      return found;
    }

    // Fallback: check if saves are alongside the exe (e.g. Perfect Dark with eeprom.bin)
    if ((await saveLikeFilesIn(Directory(gameDir))).isNotEmpty) {
      debugPrint('[WindowsSave] Saves found alongside executable: $gameDir');
      return gameDir;
    }

    debugPrint('[WindowsSave] No save directory found for ${game.name}');
    return null;
  }

  static const _saveExtensions = {
    '.sav', '.save', '.sv', '.srm', '.sra', '.eep', '.eeprom', '.fla', '.mpk', '.dsv', '.slot', '.sgm', '.gsv', '.rsv',
  };

  /// Whether [path] is named like a save: a save extension, or "save"/"eeprom" in the name (Perfect Dark's
  /// `eeprom.bin`, `save01.dat`). Used where the only clue to a save's place is the game folder itself, so
  /// the game's own data files are never mistaken for saves.
  static bool looksLikeSaveFile(String path) {
    final name = p.basename(path).toLowerCase();
    if (_saveExtensions.contains(p.extension(name))) return true;
    return name.contains('save') || name.contains('eeprom');
  }

  /// The save-like files in [dir] and the folders below it (to a depth of 3).
  static Future<List<File>> saveLikeFilesIn(Directory dir, {int maxDepth = 3}) async {
    final found = <File>[];
    Future<void> walk(Directory d, int depth) async {
      try {
        await for (final e in d.list(followLinks: false)) {
          if (e is File && looksLikeSaveFile(e.path) && await e.length() > 0) found.add(e);
          if (e is Directory && depth < maxDepth) await walk(e, depth + 1);
        }
      } catch (_) {}
    }

    await walk(dir, 1);
    return found;
  }

  /// Checks if a directory contains any save-like files (non-empty).
  Future<bool> _hasSaveFiles(Directory dir) async {
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final name = entity.path.toLowerCase();
          // Skip metadata files
          if (name.endsWith('.txt') || name.endsWith('.ini') || name.endsWith('.cfg')) continue;
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Recursively searches for a folder named "Save" or "Saves" that contains files.
  /// Limits search to 4 levels deep to avoid scanning the entire drive.
  Future<String?> _findSaveFolderRecursive(String rootDir, {int maxDepth = 4}) async {
    return _searchDir(Directory(rootDir), 0, maxDepth);
  }

  /// Parses a comma-separated filter string into a list of glob patterns.
  /// Supports: *.ext, name.*, exact names, and path prefixes (saves/*).
  static List<String> _parseFilterPatterns(String? filter) {
    if (filter == null || filter.trim().isEmpty) return [];
    return filter.split(',').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
  }

  /// Checks if a file path matches any of the filter patterns.
  static bool _matchesAnyPattern(String filePath, List<String> patterns) {
    final fileName = p.basename(filePath).toLowerCase();
    final relativePath = filePath.replaceAll('\\', '/').toLowerCase();
    for (final pattern in patterns) {
      // Exact name match
      if (fileName == pattern) return true;
      // Glob: *.ext
      if (pattern.startsWith('*.')) {
        final ext = pattern.substring(1); // e.g. ".ini"
        if (fileName.endsWith(ext)) return true;
      }
      // Glob: name.* (match any extension)
      if (pattern.endsWith('.*')) {
        final name = pattern.substring(0, pattern.length - 2); // e.g. "eeprom"
        if (fileName.startsWith(name)) return true;
      }
      // Path prefix: saves/* (match any file under a directory)
      if (pattern.endsWith('/*')) {
        final prefix = pattern.substring(0, pattern.length - 1); // e.g. "saves/"
        if (relativePath.contains(prefix)) return true;
      }
    }
    return false;
  }

  Future<String?> _searchDir(Directory dir, int depth, int maxDepth) async {
    if (depth > maxDepth) return null;
    try {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final name = p.basename(entity.path).toLowerCase();
          if (name == 'save' || name == 'saves') {
            if (await _hasSaveFiles(entity)) {
              return entity.path;
            }
          }
        }
      }
      // If no Save folder at this level, search deeper
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final name = p.basename(entity.path).toLowerCase();
          // Skip non-game folders
          if (name == '__macosx' || name == '_commonredist') continue;
          final found = await _searchDir(entity, depth + 1, maxDepth);
          if (found != null) return found;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];

    final dir = Directory(saveDir);
    if (!await dir.exists()) return [];

    // Priority is given to the user's file filter manual override
    String? filter = _saveFilters[game.id];

    // Else, we fallback to the PCGW file filter, if there's any
    if (filter == null || filter.isEmpty) filter = _wikiSaveFilters[game.id];

    final includePatterns = _parseFilterPatterns(filter);

    // When a filter (manual or PCGW) is active, return individual matching files
    // so the sync service zips only those files (not the whole directory).
    if (includePatterns.isNotEmpty) {
      final matchedFiles = <File>[];
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        if (sessionStart != null) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
        }
        if (_matchesAnyPattern(entity.path, includePatterns)) {
          matchedFiles.add(entity);
        }
      }
      return matchedFiles;
    }

    // The game folder itself stands in for the save folder (nothing better was found): only its
    // save-like files count, never the game's own data, or every launch would back up and upload the game.
    final isDirRom = await Directory(romPath).exists();
    final gameDir = isDirRom ? romPath : File(romPath).parent.path;
    if (p.equals(p.normalize(saveDir), p.normalize(gameDir))) {
      final saves = await saveLikeFilesIn(dir);
      if (sessionStart == null) return saves;
      final recent = <File>[];
      for (final f in saves) {
        if (!(await f.stat()).modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) recent.add(f);
      }
      return recent;
    }

    // No filter: check if any files exist, then return the directory.
    bool hasFiles = false;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      if (sessionStart != null) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
      }
      hasFiles = true;
      break;
    }
    if (!hasFiles) return [];

    return [File(dir.path)];
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    
    Archive? archive;
    String? envDestPath;
    if (filename.toLowerCase().endsWith('.zip')) {
      archive = ZipDecoder().decodeBytes(data);
      final metaFile = archive.find('freegosy_sync.txt');
      if (metaFile != null) {             
            String relativeEnvPath = metaFile.rawContent?.getStream().readString() ?? '';
            if (relativeEnvPath.isNotEmpty) relativeEnvPath = jsonDecode(relativeEnvPath)['savePath'];
            envDestPath = relativeEnvPath;
      }
    }

    if (envDestPath != null && envDestPath.isNotEmpty) {
      envDestPath = await fromPortablePath(game, destPath, envDestPath);
    }

    try {
      final saveDir = await getSaveDir(game, destPath, metadataSavePath: (envDestPath != null && envDestPath.isNotEmpty) ? envDestPath : null);
      if (saveDir == null) {
        throw Exception('No save location found for ${game.name}. Set one manually in game settings.');
      }

      final dir = Directory(saveDir);
      if (!await dir.exists()) await dir.create(recursive: true);
      // Always extract zip into the save directory
      if (archive!.isNotEmpty) {
        for (final entry in archive) {
          if (entry.name == 'freegosy_sync.txt' || entry.name.contains('.bak')) continue;
          
          final destDir = Directory(saveDir).parent.path;
          final entryPath = p.normalize(p.join(destDir, entry.name));
          if (entry.isFile) {
            await backupSave(entryPath);
            final outFile = File(entryPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          } else {
            await Directory(entryPath).create(recursive: true);
          }
        }
        return true;
      }

      // Fallback for non-zip (single file)
      final targetPath = p.normalize(p.join(saveDir, filename));
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      rethrow;
    }
  }
}
