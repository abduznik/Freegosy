import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../romm/romm_models.dart';
import '../../windows/pcgamingwiki_service.dart';
import '../save_strategy.dart';
import 'package:dio/dio.dart';

class WindowsSaveStrategy extends SaveStrategy {
  final PcGamingWikiService _wikiService;

  // Manual override paths set by user per game id
  final Map<String, String> _manualOverrides = {};

  WindowsSaveStrategy() : _wikiService = PcGamingWikiService(Dio());

  @override
  String get strategyId => 'windows';

  /// Allows the user to manually set a save path for a game.
  static const String _prefsPrefix = 'win_save_';

  Future<void> loadPersistedOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefsPrefix));
    for (final key in keys) {
      final gameId = key.substring(_prefsPrefix.length);
      final path = prefs.getString(key);
      if (path != null && path.isNotEmpty) _manualOverrides[gameId] = path;
    }
  }

  /// Allows the user to manually set a save path for a game.
  Future<void> setManualOverride(String gameId, String path) async {
    _manualOverrides[gameId] = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefsPrefix$gameId', path);
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

    // Package the entire save directory as a single zip
    final zipPath = '${dir.path}.saves.zip';
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await encoder.addDirectory(dir);
    encoder.close();

    return [File(zipPath)];
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
          final entryPath = '$saveDir/${entry.name}';
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
      final targetPath = '$saveDir/$filename';
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      rethrow;
    }
  }
}
