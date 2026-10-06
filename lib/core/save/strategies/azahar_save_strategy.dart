import 'dart:io' as io;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../platform/platform_info.dart';
import '../../romm/game_id_resolver.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

// ─── Strategy ────────────────────────────────────────────────────────────────

/// Save strategy for Azahar (Nintendo 3DS) emulator.
///
/// Follows the Eden pattern: requires manual folder mapping from the 'sdmc' 
/// directory if automatic resolution is not possible.
class AzaharSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;
  // ignore: unused_field
  final PlatformInfo _platform;
  final Future<void> Function(String gameId, String mapping)? onMappingResolved;

  AzaharSaveStrategy(this._directoryService, {this.onMappingResolved, PlatformInfo? platform})
      : _platform = platform ?? PlatformInfo.current;

  @override
  String get strategyId => 'azahar';

  @override
  bool get supportsSaveSync => true;

  String? _manualMapping;

  /// Sets the manual mapping (relative path from sdmc directory).
  void setManualMapping(String? mapping) {
    _manualMapping = mapping;
  }

  String _getAzaharExe() {
    if (_platform.isWindows) return 'azahar.exe';
    if (_platform.isMacOS) return 'azahar.app/Contents/MacOS/azahar';
    return 'azahar';
  }

  /// Resolves Azahar's data root (the folder that directly contains 'sdmc').
  ///
  /// Follows the Eden pattern: portable installs keep their data in a 'user'
  /// folder next to the executable, so that is checked first. Only falls
  /// back to the OS-standard config location (NOT the shared BIOS/system
  /// directory, which is unrelated to per-emulator save data) if no
  /// portable 'user' folder exists.
  Future<String> _getAzaharSaveBase({String? platformSlug}) async {
    final exePath = await _directoryService.findEmulatorExecutable('azahar', _getAzaharExe());
    if (exePath != null) {
      String exeDir = io.File(exePath).parent.path;
      if (_platform.isMacOS && exePath.contains('.app/Contents/MacOS/')) {
        exeDir = io.File(exePath).parent.parent.parent.parent.path;
      } else if (await io.FileSystemEntity.isDirectory(exePath)) {
        exeDir = exePath;
      }
      final portableBase = p.join(exeDir, 'user');
      debugPrint('[Azahar] exe=$exePath -> checking portable data at: $portableBase');
      if (await io.Directory(portableBase).exists()) {
        debugPrint('[Azahar] portable data base found: $portableBase');
        return portableBase;
      }
      debugPrint('[Azahar] portable data missing at: $portableBase');
    } else {
      debugPrint('[Azahar] no azahar executable found via DirectoryService');
    }

    final String resolvedPath;
    if (_platform.isMacOS || _platform.isLinux) {
      resolvedPath = await _directoryService.getEmulatorAppSupportDirectory('azahar', platformSlug: platformSlug);
    } else if (_platform.isWindows) {
      resolvedPath = p.join(_platform.environment['APPDATA'] ?? '', 'azahar');
    } else {
      throw UnsupportedError('Platform not supported');
    }
    debugPrint('[Azahar] standard data base candidate: $resolvedPath');
    if (!await io.Directory(resolvedPath).exists()) {
      throw Exception('Save directory not found for Azahar at $resolvedPath. Please launch Azahar at least once to generate save data.');
    }
    return resolvedPath;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final manual = GameIdResolver.clean(_manualMapping);
    final fromRomm = manual == null ? GameIdResolver.server('Azahar ${game.name}', rommTitlePath(game.saveTarget)) : null;
    if (manual == null && fromRomm == null) {
      debugPrint('[Azahar] FAILED: No manual mapping resolved for ${game.name}');
      throw SaveMappingRequiredException(
          'Could not determine save folder for "${game.name}". '
          'Please select the save folder manually from the sdmc directory.');
    }

    final base = await _getAzaharSaveBase(platformSlug: game.platformSlug);
    // A mapping is the folder's path from sdmc, as the folder dialog gives it.
    final mapping = manual ?? await mappingFromSaveTarget(base, fromRomm!);
    final finalPath = p.join(base, 'sdmc', mapping);
    debugPrint('[Azahar] Final path: $finalPath');
    return finalPath;
  }

  /// RomM's 3DS `save_target` as `<high>/<low>` of the base game's title:
  /// `00040000/00033500`, also from a flat `0004000000033500`. An update's
  /// (`0004000e`) or DLC's (`0004008c`) id becomes the game's, where the
  /// save is. Null for anything else.
  @visibleForTesting
  static String? rommTitlePath(String? saveTarget) {
    var id = GameIdResolver.clean(saveTarget)?.toLowerCase();
    if (id == null) return null;
    if (RegExp(r'^[0-9a-f]{16}$').hasMatch(id)) id = '${id.substring(0, 8)}/${id.substring(8)}';
    if (RegExp(r'^[0-9a-f]{8}$').hasMatch(id)) id = '00040000/$id'; // no category: the game's
    if (!RegExp(r'^[0-9a-f]{8}/[0-9a-f]{8}$').hasMatch(id)) return null;
    final high = id.substring(0, 8);
    return high == '0004000e' || high == '0004008c' ? '00040000${id.substring(8)}' : id;
  }

  /// The sdmc-relative folder of a title's save data, as the folder dialog
  /// gives it: `Nintendo 3DS/<id0>/<id1>/title/<high>/<low>/data/00000001`.
  /// [saveTarget] is RomM's `<high>/<low>` (`00040000/00033500`). The
  /// `<id0>/<id1>` pair is the one already holding this title, else the only
  /// one there, else Azahar's default (32 zeros each).
  @visibleForTesting
  static Future<String> mappingFromSaveTarget(String base, String saveTarget) async {
    final titlePath = saveTarget.toLowerCase().split('/');
    String under(String id0, String id1) =>
        p.joinAll(['Nintendo 3DS', id0, id1, 'title', ...titlePath, 'data', '00000001']);

    final pairs = <(String, String)>[];
    final root = io.Directory(p.join(base, 'sdmc', 'Nintendo 3DS'));
    if (await root.exists()) {
      await for (final id0 in root.list()) {
        if (id0 is! io.Directory) continue;
        await for (final id1 in id0.list()) {
          if (id1 is io.Directory) pairs.add((p.basename(id0.path), p.basename(id1.path)));
        }
      }
    }
    for (final (id0, id1) in pairs) {
      if (await io.Directory(p.join(base, 'sdmc', under(id0, id1))).exists()) return under(id0, id1);
    }
    if (pairs.length == 1) return under(pairs.single.$1, pairs.single.$2);
    const zeros = '00000000000000000000000000000000';
    return under(zeros, zeros);
  }

  @override
  Future<List<io.File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];

    final dir = io.Directory(saveDir);
    if (!dir.existsSync()) {
      if (syncMode == 'push') {
        throw Exception('Local save data not found for pushing.');
      }
      return [];
    }

    // Check if directory actually contains save files
    final hasFiles = dir.listSync(recursive: true).any((f) => f is io.File);
    if (!hasFiles) {
      if (syncMode == 'push') {
        throw Exception('Save directory exists but contains no save files.');
      }
      return [];
    }

    // If sessionStart filter is set, check if any file was modified after it
    if (sessionStart != null) {
      final files = dir.listSync(recursive: true).whereType<io.File>();
      final hasChanges = files.any((f) => f.statSync().modified.isAfter(sessionStart.subtract(const Duration(seconds: 2))));
      if (!hasChanges) {
        debugPrint('[Azahar] No files modified since session start');
        return [];
      }
    }

    // Return the DIRECTORY as a File reference.
    // SaveSyncService.pushSaves() detects isDirectory and zips it.
    return [io.File(saveDir)];
  }

  @override
  Future<bool> restoreSave(
    Game game,
    String destPath,
    Uint8List data,
    String filename,
  ) async {
    try {
      debugPrint('=== AZAHAR RESTORE: ${game.name} ===');
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) return false;

      final dir = io.Directory(saveDir);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        return await _extractArchive(archive, saveDir);
      } else {
        final filePath = p.normalize(p.join(saveDir, filename));
        await backupSave(filePath);
        await io.File(filePath).writeAsBytes(data);
        debugPrint('[Azahar][Restore] Wrote single file: $filePath');
        return true;
      }
    } catch (e) {
      if (e is SaveMappingRequiredException) {
        rethrow;
      }
      debugPrint('[Azahar][Restore] ERROR: $e');
      rethrow;
    }
  }

  /// Extracts a ZIP archive into [destDir], stripping a leading folder if present.
  Future<bool> _extractArchive(Archive archive, String destDir) async {
    try {
      for (final entry in archive) {
        if (entry.name.isEmpty || entry.name == 'freegosy_sync.txt' || entry.name.contains('.bak')) continue;

        // Strip leading folder if present (e.g. "00000001/save.bin" -> "save.bin")
        final segments = entry.name.split(RegExp(r'[/\\]'));
        final entryPath = (segments.length > 1)
            ? p.joinAll(segments.sublist(1))
            : entry.name;

        if (entryPath.isEmpty) continue;

        final outPath = p.normalize(p.join(destDir, entryPath));
        if (entry.isFile) {
          await backupSave(outPath);
          final outFile = io.File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
          debugPrint('[Azahar][Extract] ${entry.name} → $outPath');
        } else {
          await io.Directory(outPath).create(recursive: true);
        }
      }
      return true;
    } catch (e) {
      debugPrint('[Azahar][Extract] ERROR: $e');
      rethrow;
    }
  }

  /// Scans the 'sdmc' directory for available save data folders.
  /// Looks for '00000001' folders which are typical for 3DS saves.
  Future<List<Map<String, dynamic>>> getAvailableSaveFolders() async {
    final base = await _getAzaharSaveBase();

    final sdmcDir = io.Directory(p.join(base, 'sdmc'));
    if (!sdmcDir.existsSync()) {
      debugPrint('[Azahar] sdmc directory not found at: ${sdmcDir.path}');
      return [];
    }

    final folders = <Map<String, dynamic>>[];
    final hex16Regex = RegExp(r'^[0-9A-Fa-f]{16}$');
    
    try {
      await for (final entity in sdmcDir.list(recursive: true, followLinks: false)) {
        if (entity is io.Directory) {
          final name = p.basename(entity.path);
          if (name == '00000001') {
            // It's a save data folder
            DateTime? newest;
            int fileCount = 0;
            
            try {
              for (final f in entity.listSync(recursive: true)) {
                if (f is! io.File) continue;
                final fname = p.basename(f.path);
                if (fname.startsWith('.') || fname.endsWith('.bak')) continue;

                fileCount++;
                final stat = f.statSync();
                if (newest == null || stat.modified.isAfter(newest)) {
                  newest = stat.modified;
                }
              }
            } catch (_) {}

            if (fileCount > 0) {
              final relativePath = p.relative(entity.path, from: sdmcDir.path);
              
              // Try to find a Title ID in the path (typically 16-hex)
              String displayName = relativePath;
              final segments = p.split(relativePath);
              for (int i = segments.length - 1; i >= 0; i--) {
                if (segments[i].length == 16 && hex16Regex.hasMatch(segments[i])) {
                  displayName = segments[i];
                  break;
                }
              }

              folders.add({
                'name': displayName,
                'path': relativePath,
                'lastModified': newest ?? entity.statSync().modified,
                'fileCount': fileCount,
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Azahar] Error scanning folders: $e');
    }

    folders.sort((a, b) => (b['lastModified'] as DateTime)
        .compareTo(a['lastModified'] as DateTime));
    return folders;
  }
}
