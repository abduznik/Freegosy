import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../romm/romm_models.dart';
import '../../windows/pcgamingwiki_service.dart';
import '../save_strategy.dart';
import 'package:dio/dio.dart';

class WindowsSaveStrategy extends SaveStrategy {
  final PcGamingWikiService _wikiService;
  final SharedPreferences _prefs;

  // Manual override paths set by user per game id
  final Map<String, String> _manualOverrides = {};

  WindowsSaveStrategy(this._prefs) : _wikiService = PcGamingWikiService(Dio());

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

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    // Manual override takes priority
    final manual = _manualOverrides[game.id];
    if (manual != null && manual.isNotEmpty) return manual;

    // Try PCGamingWiki
    try {
      final locations = await _wikiService.getSaveLocations(game.name);
      if (locations.isNotEmpty) {
        return locations.first['path'];
      }
    } catch (e) {
      //
    }

    return null;
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];

    final dir = Directory(saveDir);
    if (!await dir.exists()) return [];

    // Check if any files exist (respecting sessionStart)
    bool hasFiles = false;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      if (sessionStart != null) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(sessionStart)) continue;
      }
      hasFiles = true;
      break;
    }
    if (!hasFiles) return [];

    // Return the directory itself (wrapped in File for the strategy API)
    // SaveSyncService will add it as a directory to the bundle zip.
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
