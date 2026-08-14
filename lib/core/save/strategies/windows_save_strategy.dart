import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../platform/platform_info.dart';
import '../../romm/romm_models.dart';
import '../../storage/app_preferences.dart';
import '../../windows/pcgamingwiki_service.dart';
import '../save_strategy.dart';
import 'package:dio/dio.dart';

class WindowsSaveStrategy extends SaveStrategy {
  final PcGamingWikiService _wikiService;
  final AppPreferences _prefs;
  // ignore: unused_field
  final PlatformInfo _platform;

  // Manual override paths set by user per game id
  final Map<String, String> _manualOverrides = {};
  // Save file filter patterns per game id (comma-separated: "*.ini, *.bin, eeprom.*")
  final Map<String, String> _saveFilters = {};

  WindowsSaveStrategy(this._prefs, {PlatformInfo? platform})
      : _wikiService = PcGamingWikiService(Dio()),
        _platform = platform ?? PlatformInfo.current;

  @override
  String get strategyId => 'windows';

  /// Allows the user to manually set a save path for a game.
  static const String _prefsPrefix = 'win_save_';

  void loadPersistedOverrides() {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefsPrefix));
    for (final key in keys) {
      final gameId = key.substring(_prefsPrefix.length);
      final path = _prefs.getString(key);
      if (path != null && path.isNotEmpty) _manualOverrides[gameId] = path;
    }
  }

  /// Allows the user to manually set a save path for a game.
  Future<void> setManualOverride(String gameId, String path) async {
    _manualOverrides[gameId] = path;
    await _prefs.setString('$_prefsPrefix$gameId', path);
  }

  String? getManualOverride(String gameId) => _manualOverrides[gameId];

  static const String _filterPrefix = 'win_filter_';

  void loadPersistedFilters() {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_filterPrefix));
    for (final key in keys) {
      final gameId = key.substring(_filterPrefix.length);
      final filter = _prefs.getString(key);
      if (filter != null) _saveFilters[gameId] = filter;
    }
  }

  Future<void> setSaveFilter(String gameId, String filter) async {
    _saveFilters[gameId] = filter;
    await _prefs.setString('$_filterPrefix$gameId', filter);
  }

  String? getSaveFilter(String gameId) => _saveFilters[gameId];

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    // Manual override takes priority
    final manual = _manualOverrides[game.id];
    if (manual != null && manual.isNotEmpty) {
      debugPrint('[WindowsSave] Using manual override for ${game.name}: $manual');
      return manual;
    }

    // Determine the game directory
    final isDir = await Directory(romPath).exists();
    final gameDir = isDir ? romPath : File(romPath).parent.path;

    // Try PCGamingWiki
    try {
      debugPrint('[WindowsSave] Querying PCGamingWiki for ${game.name}...');
      final locations = await _wikiService.getSaveLocations(game.name, gameDir: gameDir);
      if (locations.isNotEmpty) {
        debugPrint('[WindowsSave] PCGamingWiki found ${locations.length} save location(s):');
        for (final loc in locations) {
          debugPrint('[WindowsSave]   raw: ${loc['raw']} → path: ${loc['path']}');
        }
        final resolved = locations.first['path'];
        if (resolved != null) {
          final dir = Directory(resolved);
          if (await dir.exists()) {
            // Check if this directory actually has save files
            if (await _hasSaveFiles(dir)) {
              debugPrint('[WindowsSave] PCGamingWiki dir has save files: $resolved');
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
    if (await _hasSaveFiles(Directory(gameDir))) {
      debugPrint('[WindowsSave] Saves found alongside executable: $gameDir');
      return gameDir;
    }

    debugPrint('[WindowsSave] No save directory found for ${game.name}');
    return null;
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

    final filter = _saveFilters[game.id];
    final includePatterns = _parseFilterPatterns(filter);

    // When a filter is active, return individual matching files
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
    try {
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) {
        throw Exception('No save location found for ${game.name}. Set one manually in game settings.');
      }

      final dir = Directory(saveDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      // Always extract zip into the save directory
      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          if (entry.name == 'freegosy_sync.txt' || entry.name.contains('.bak')) continue;
          
          final entryPath = p.normalize(p.join(saveDir, entry.name));
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
