import 'dart:io' as io;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../save_strategy.dart';
import 'eden_save_strategy.dart'; // Reuse exceptions and some logic

/// Save strategy for Ryujinx (Switch) emulator.
class RyujinxSaveStrategy extends SaveStrategy {
  final Future<void> Function(String gameId, String titleId)? onMappingResolved;

  RyujinxSaveStrategy({this.onMappingResolved});

  @override
  String get strategyId => 'switch_ryujinx';

  @override
  bool get supportsSaveSync => true;

  // ── Regex library ──────────────────────────────────────────────────────────

  static final RegExp _strictTitleIdRegex = RegExp(r'^01[0-9A-Fa-f]{14}$');
  static final RegExp _titleIdExtractorRegex = RegExp(r'01[0-9A-Fa-f]{14}');
  static final RegExp _cnmtRegex = RegExp(r'(01[0-9A-Fa-f]{14})\.cnmt', caseSensitive: false);
  static final RegExp _userIdRegex = RegExp(r'^[0-9A-Fa-f]{16}$');
  static const _romExtensions = ['.nsp', '.xci', '.nsz'];

  // ── Mutable state ──────────────────────────────────────────────────────────

  String? _manualMapping;
  String? _activeProfileOverride;

  void setManualMapping(String? titleId) => _manualMapping = titleId;
  void setActiveProfileOverride(String? profileId) => _activeProfileOverride = profileId;

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 1 — Title ID Resolution
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _resolveTitleId(String romPath, Game game) async {
    // 1. Header byte scan
    final (fromHeader, resolvedRomPath) = await _extractTitleIdFromHeader(romPath);
    if (fromHeader != null) {
      debugPrint('[Ryujinx] Title ID from header: $fromHeader');
      if (onMappingResolved != null) {
        await onMappingResolved!(game.id, fromHeader);
      }
      return fromHeader;
    }

    // 2. Extract from ROM filename
    final fromFilename = _extractTitleIdFromFilename(resolvedRomPath ?? romPath, game);
    if (fromFilename != null) {
      debugPrint('[Ryujinx] Title ID from filename: $fromFilename');
      if (onMappingResolved != null) {
        await onMappingResolved!(game.id, fromFilename);
      }
      return fromFilename;
    }

    // 3. Manual mapping
    if (_manualMapping != null && _manualMapping!.isNotEmpty) {
      debugPrint('[Ryujinx] Title ID from manual mapping: $_manualMapping');
      return _manualMapping!;
    }

    // 4. Nothing worked
    debugPrint('[Ryujinx] FAILED: No Title ID resolved for ${game.name}');
    throw SaveMappingRequiredException(
        'Could not determine Title ID for "${game.name}". '
        'Please select the save folder manually.');
  }

  String? _extractTitleIdFromFilename(String romPath, Game game) {
    for (final candidate in [p.basename(romPath), game.fileName ?? '', game.name]) {
      if (candidate.isEmpty) continue;
      final match = _titleIdExtractorRegex.firstMatch(candidate);
      if (match != null) {
        return _normalizeToBaseId(match.group(0)!);
      }
    }
    return null;
  }

  Future<(String? titleId, String? resolvedPath)> _extractTitleIdFromHeader(String romPath) async {
    final actualPath = await _resolveRomFile(romPath);
    if (actualPath == null) return (null, null);

    try {
      final file = io.File(actualPath);
      final raf = await file.open();
      final bytes = await raf.read(262144); // 256 KB
      await raf.close();

      final content = String.fromCharCodes(bytes);
      final match = _cnmtRegex.firstMatch(content);
      if (match != null) {
        return (_normalizeToBaseId(match.group(1)!), actualPath);
      }
    } catch (e) {
      debugPrint('[Ryujinx][Scanner] ERROR: $e');
    }
    return (null, actualPath);
  }

  static String _normalizeToBaseId(String raw) {
    final upper = raw.toUpperCase();
    if (upper.length == 16) {
      return '${upper.substring(0, 13)}000';
    }
    return upper;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 2 — User ID / Profile Resolution
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _resolveUserId(String baseSavePath) async {
    if (_activeProfileOverride != null && _activeProfileOverride!.isNotEmpty) {
      return _activeProfileOverride!;
    }

    final dir = io.Directory(baseSavePath);
    if (!dir.existsSync()) {
      throw Exception('Ryujinx save base does not exist: ${dir.path}');
    }

    final candidates = <Map<String, dynamic>>[];
    for (final entity in dir.listSync()) {
      if (entity is! io.Directory) continue;
      final name = p.basename(entity.path);
      if (!_userIdRegex.hasMatch(name)) continue;

      DateTime? newestFileTime;
      int saveFileCount = 0;

      for (final saveDir in entity.listSync()) {
        if (saveDir is! io.Directory) continue;
        try {
          for (final file in saveDir.listSync(recursive: true)) {
            if (file is! io.File) continue;
            final fname = p.basename(file.path);
            if (fname.startsWith('.') || fname.endsWith('.bak')) continue;

            saveFileCount++;
            final stat = file.statSync();
            if (newestFileTime == null || stat.modified.isAfter(newestFileTime)) {
              newestFileTime = stat.modified;
            }
          }
        } catch (_) {}
      }

      if (newestFileTime != null && saveFileCount > 0) {
        candidates.add({
          'id': name,
          'newestFile': newestFileTime,
          'fileCount': saveFileCount,
        });
      }
    }

    if (candidates.isEmpty) {
      // Fallback to 0000000000000001 if it exists
      if (io.Directory(p.join(baseSavePath, '0000000000000001')).existsSync()) {
        return '0000000000000001';
      }
      throw Exception('No active Ryujinx users found in ${dir.path}.');
    }

    candidates.sort((a, b) => (b['newestFile'] as DateTime).compareTo(a['newestFile'] as DateTime));

    if (candidates.length == 1) return candidates.first['id'] as String;

    final winner = candidates[0];
    final runnerUp = candidates[1];
    final gap = (winner['newestFile'] as DateTime).difference(runnerUp['newestFile'] as DateTime);

    if (gap.inHours >= 1 || (runnerUp['fileCount'] as int) <= 1) {
      return winner['id'] as String;
    }

    throw ProfileConflictException(candidates);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ROM file resolution (fuzzy matching)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> _resolveRomFile(String romPath) async {
    if (io.File(romPath).existsSync()) return romPath;
    for (final ext in _romExtensions) {
      final withExt = '$romPath$ext';
      if (io.File(withExt).existsSync()) return withExt;
    }
    if (io.Directory(romPath).existsSync()) return _findLargestRomInDir(romPath);
    return null;
  }

  String? _findLargestRomInDir(String dirPath) {
    io.File? largest;
    int maxSize = -1;
    try {
      for (final entity in io.Directory(dirPath).listSync(recursive: true)) {
        if (entity is! io.File) continue;
        final name = entity.path.toLowerCase();
        if (!_romExtensions.any((ext) => name.endsWith(ext))) continue;
        final size = entity.lengthSync();
        if (size > maxSize) {
          maxSize = size;
          largest = entity;
        }
      }
    } catch (_) {}
    return largest?.path;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Platform-specific save base path
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _getRyujinxSaveBase({String? platformSlug}) async {
    final String resolvedPath;
    if (io.Platform.isMacOS) {
      final home = io.Platform.environment['HOME'] ?? '';
      resolvedPath = p.join(home, 'Library', 'Application Support', 'Ryujinx');
    } else if (io.Platform.isLinux) {
      final home = io.Platform.environment['HOME'] ?? '';
      resolvedPath = p.join(home, '.config', 'Ryujinx');
    } else if (io.Platform.isWindows) {
      final appData = io.Platform.environment['APPDATA'] ?? '';
      resolvedPath = p.join(appData, 'Ryujinx');
    } else {
      throw UnsupportedError('Platform not supported for Ryujinx save path resolution');
    }

    final finalPath = p.join(resolvedPath, 'bis', 'user', 'save');
    if (!await io.Directory(finalPath).exists()) {
      throw Exception('Save directory not found for Ryujinx at $finalPath.');
    }
    return finalPath;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Public API — SaveStrategy overrides
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final base = await _getRyujinxSaveBase(platformSlug: game.platformSlug);
    final userId = await _resolveUserId(base);
    final titleId = await _resolveTitleId(romPath, game);
    final userDirPath = p.join(base, userId);

    debugPrint('[Ryujinx] getSaveDir: userDirPath=$userDirPath, targetTitleId=$titleId');

    // Scan for ExtraData0, ExtraData1... in the UserID folder
    final userDir = io.Directory(userDirPath);
    if (userDir.existsSync()) {
      for (int i = 0; i < 100; i++) {
        final extraDataFile = io.File(p.join(userDirPath, 'ExtraData$i'));
        if (!extraDataFile.existsSync()) break;

        try {
          final bytes = await extraDataFile.readAsBytes();
          if (bytes.length >= 8) {
            // Title ID is at offset 0, 8 bytes, little-endian
            final extractedTitleId = bytes.sublist(0, 8).reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
            final normalizedExtracted = _normalizeToBaseId(extractedTitleId);
            final normalizedTarget = _normalizeToBaseId(titleId);

            debugPrint('[Ryujinx] ExtraData$i: found=$normalizedExtracted, target=$normalizedTarget');

            if (normalizedExtracted == normalizedTarget) {
              final slotDir = p.join(userDirPath, '$i');
              debugPrint('[Ryujinx] Match found! Slot folder: $slotDir');
              return slotDir;
            }
          }
        } catch (e) {
          debugPrint('[Ryujinx] Error reading ExtraData$i: $e');
        }
      }
    }

    // Default to slot 0 if no match found
    final defaultDir = p.join(userDirPath, '0');
    debugPrint('[Ryujinx] No match found, defaulting to slot 0: $defaultDir');
    return defaultDir;
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];
    final dir = io.Directory(saveDir);
    if (!dir.existsSync()) return [];

    final files = dir.listSync(recursive: true).whereType<io.File>().where((f) {
      final name = p.basename(f.path);
      return !name.startsWith('.') && !name.endsWith('.bak');
    }).toList();

    if (files.isEmpty) return [];

    if (sessionStart != null) {
      final hasChanges = files.any((f) => f.statSync().modified.isAfter(sessionStart));
      if (!hasChanges) return [];
    }

    return [io.File(saveDir)];
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    final base = await _getRyujinxSaveBase(platformSlug: game.platformSlug);
    final userId = await _resolveUserId(base);
    final titleId = await _resolveTitleId(destPath, game);
    
    debugPrint('[Ryujinx] Restore: userId=$userId, titleId=$titleId');

    final targetPath = await getSaveDir(game, destPath);
    if (targetPath == null) throw Exception('Could not resolve Ryujinx save directory');
    
    debugPrint('[Ryujinx] Restore: targeting slot folder $targetPath');

    // Ensure target path exists
    if (!io.Directory(targetPath).existsSync()) {
      io.Directory(targetPath).createSync(recursive: true);
    }

    bool success = false;
    if (filename.toLowerCase().endsWith('.zip')) {
      final archive = ZipDecoder().decodeBytes(data);
      success = await _extractArchive(archive, targetPath, titleId: titleId);
    } else {
      final filePath = p.normalize(p.join(targetPath, filename));
      await backupSave(filePath);
      await io.File(filePath).writeAsBytes(data);
      success = true;
    }

    // Cleanup: Remove any subfolders under UserID folder that are named with a 16-char Title ID
    final userDir = io.Directory(p.join(base, userId));
    if (userDir.existsSync()) {
      for (final entity in userDir.listSync()) {
        if (entity is io.Directory) {
          final name = p.basename(entity.path);
          if (_strictTitleIdRegex.hasMatch(name)) {
            debugPrint('[Ryujinx] Cleanup: removing invalid Title ID folder $name');
            try {
              entity.deleteSync(recursive: true);
            } catch (e) {
              debugPrint('[Ryujinx] Cleanup failed for $name: $e');
            }
          }
        }
      }
    }

    return success;
  }

  /// Lists all Title ID save folders for the active profile.
  /// Used by the UI for manual folder selection.
  Future<List<Map<String, dynamic>>> getAvailableSaveFolders() async {
    final base = await _getRyujinxSaveBase();
    String userId;
    try {
      userId = await _resolveUserId(base);
    } catch (_) {
      // Fallback to first user found
      final dir = io.Directory(base);
      if (dir.existsSync()) {
        final users = dir.listSync().whereType<io.Directory>().where((d) => _userIdRegex.hasMatch(p.basename(d.path))).toList();
        if (users.isNotEmpty) {
          userId = p.basename(users.first.path);
        } else {
          return [];
        }
      } else {
        return [];
      }
    }

    final userDir = io.Directory(p.join(base, userId));
    if (!userDir.existsSync()) return [];

    final folders = <Map<String, dynamic>>[];
    for (final entity in userDir.listSync()) {
      if (entity is! io.Directory) continue;
      final name = p.basename(entity.path);
      
      String? displayName = name;
      final extraData = io.File(p.join(entity.path, 'ExtraData0'));
      if (extraData.existsSync()) {
        try {
          final bytes = await extraData.readAsBytes();
          if (bytes.length >= 8) {
            displayName = bytes.sublist(0, 8).reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
          }
        } catch (_) {}
      }

      DateTime? newest;
      int fileCount = 0;
      for (final f in entity.listSync(recursive: true)) {
        if (f is! io.File) continue;
        final fname = p.basename(f.path);
        if (fname == 'ExtraData0' || fname.startsWith('.') || fname.endsWith('.bak')) continue;
        fileCount++;
        final mod = f.statSync().modified;
        if (newest == null || mod.isAfter(newest)) newest = mod;
      }

      if (fileCount > 0) {
        folders.add({
          'name': displayName,
          'path': name, // folder name is the path
          'lastModified': newest ?? entity.statSync().modified,
          'fileCount': fileCount,
        });
      }
    }

    folders.sort((a, b) => (b['lastModified'] as DateTime).compareTo(a['lastModified'] as DateTime));
    return folders;
  }

  Future<bool> _extractArchive(Archive archive, String destDir, {String? titleId}) async {
    for (final entry in archive) {
      if (entry.name.isEmpty || entry.name == 'freegosy_sync.txt' || entry.name.contains('.bak')) continue;
      
      // Strip container folders: Title ID, User ID, or a numeric index (0, 1, 2...).
      final segments = entry.name.split(RegExp(r'[/\\]'));
      var currentSegments = List<String>.from(segments);
      
      while (currentSegments.length > 1) {
        final first = currentSegments.first;
        final isTitleId = _strictTitleIdRegex.hasMatch(first) || (titleId != null && first.toUpperCase() == titleId.toUpperCase());
        final isUserId = _userIdRegex.hasMatch(first);
        final isNumeric = RegExp(r'^\d+$').hasMatch(first);

        if (isTitleId || isUserId || isNumeric) {
          currentSegments.removeAt(0);
        } else {
          break;
        }
      }
      
      final entryPath = p.joinAll(currentSegments);
      if (entryPath.isEmpty) continue;

      debugPrint('[Ryujinx] Restore Entry: "${entry.name}" -> "$entryPath"');
      
      final outPath = p.normalize(p.join(destDir, entryPath));
      if (entry.isFile) {
        await backupSave(outPath);
        final outFile = io.File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
      } else {
        await io.Directory(outPath).create(recursive: true);
      }
    }
    return true;
  }
}
