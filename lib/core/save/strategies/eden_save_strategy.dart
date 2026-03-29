import 'dart:io' as io;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../save_strategy.dart';

// ─── Exceptions ──────────────────────────────────────────────────────────────

class SaveMappingRequiredException implements Exception {
  final String message;
  SaveMappingRequiredException([this.message = 'Manual save mapping required']);
  @override
  String toString() => 'SaveMappingRequiredException: $message';
}

class ProfileConflictException implements Exception {
  final List<Map<String, dynamic>> profiles;
  ProfileConflictException(this.profiles);
  @override
  String toString() =>
      'ProfileConflictException: ${profiles.length} active profiles found.';
}

// ─── Strategy ────────────────────────────────────────────────────────────────

/// Save strategy for Eden (Switch) emulator.
///
/// Resolution order for Title ID:
///   1. ROM header byte scan (.cnmt string in first 256 KB)
///   2. Title ID extracted from ROM filename  e.g. [0100704000B3A000]
///   3. Manual mapping stored in SharedPreferences
///   4. Throw [SaveMappingRequiredException] → UI shows folder picker
///
/// Resolution order for Profile ID:
///   1. Manual override (user picked from conflict dialog)
///   2. Recency heuristic on actual save *files* (not dir mtime)
///   3. Throw [ProfileConflictException] → UI shows profile picker
class EdenSaveStrategy extends SaveStrategy {
  final Future<void> Function(String gameId, String titleId)?
      onMappingResolved;

  EdenSaveStrategy({this.onMappingResolved});

  @override
  String get strategyId => 'switch';

  @override
  bool get supportsSaveSync => true;

  // ── Regex library ──────────────────────────────────────────────────────────

  /// Matches a valid 16-char Switch Title ID anchored to full string.
  static final RegExp _strictTitleIdRegex =
      RegExp(r'^01[0-9A-Fa-f]{14}$');

  /// Extracts a 16-char Title ID anywhere in a string.
  static final RegExp _titleIdExtractorRegex =
      RegExp(r'01[0-9A-Fa-f]{14}');

  /// Finds `<TitleID>.cnmt` in raw byte content (the header scanner).
  static final RegExp _cnmtRegex =
      RegExp(r'(01[0-9A-Fa-f]{14})\.cnmt', caseSensitive: false);

  /// Matches a 32-char hex string (Eden profile folder name).
  static final RegExp _profileRegex = RegExp(r'^[0-9A-Fa-f]{32}$');

  /// ROM file extensions we care about.
  static const _romExtensions = ['.nsp', '.xci', '.nsz'];

  // ── Mutable state (set per-sync from SaveSyncService) ──────────────────────

  String? _manualMapping;
  String? _activeProfileOverride;

  void setManualMapping(String? titleId) => _manualMapping = titleId;
  void setActiveProfileOverride(String? profileId) =>
      _activeProfileOverride = profileId;

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 1 — Title ID Resolution
  // ═══════════════════════════════════════════════════════════════════════════

  /// Master resolver: header → filename → manual mapping → throw.
  Future<String> _resolveTitleId(String romPath, Game game) async {
    // 1. Header byte scan (the source of truth)
    final (fromHeader, resolvedRomPath) =
        await extractTitleIdFromHeader(romPath);
    if (fromHeader != null) {
      debugPrint('[Eden] Title ID from header: $fromHeader');
      // Persist so future syncs skip the scan
      if (onMappingResolved != null) {
        await onMappingResolved!(game.id, fromHeader);
      }
      return fromHeader;
    }

    // 2. Extract from ROM filename  e.g. "Splatoon 3 [0100C2500FC20000][v0].nsp"
    final fromFilename =
        _extractTitleIdFromFilename(resolvedRomPath ?? romPath, game);
    if (fromFilename != null) {
      debugPrint('[Eden] Title ID from filename: $fromFilename');
      if (onMappingResolved != null) {
        await onMappingResolved!(game.id, fromFilename);
      }
      return fromFilename;
    }

    // 3. Manual mapping (SharedPreferences, set by SaveSyncService)
    if (_manualMapping != null && _manualMapping!.isNotEmpty) {
      debugPrint('[Eden] Title ID from manual mapping: $_manualMapping');
      return _manualMapping!;
    }

    // 4. Nothing worked
    debugPrint('[Eden] FAILED: No Title ID resolved for ${game.name}');
    throw SaveMappingRequiredException(
        'Could not determine Title ID for "${game.name}". '
        'Please select the save folder manually.');
  }

  /// Tries to pull a Title ID from the ROM's filename or the Game model name.
  String? _extractTitleIdFromFilename(String romPath, Game game) {
    // Try the actual file path first, then game.fileName, then game.name
    for (final candidate in [
      p.basename(romPath),
      game.fileName ?? '',
      game.name,
    ]) {
      if (candidate.isEmpty) continue;
      final match = _titleIdExtractorRegex.firstMatch(candidate);
      if (match != null) {
        return _normalizeToBaseId(match.group(0)!);
      }
    }
    return null;
  }

  /// Scans the first 256 KB of a ROM for `<TitleID>.cnmt` strings.
  ///
  /// If [romPath] doesn't point to an actual file, this method:
  ///   1. Tries appending .nsp / .xci / .nsz
  ///   2. Fuzzy-searches the parent directory for a matching ROM
  ///   3. If the path is a directory, picks the largest ROM inside
  Future<(String? titleId, String? resolvedPath)> extractTitleIdFromHeader(
      String romPath) async {
    final actualPath = await _resolveRomFile(romPath);
    if (actualPath == null) {
      debugPrint('[Eden][Scanner] No ROM file found for: $romPath');
      return (null, null);
    }

    debugPrint('[Eden][Scanner] Reading: $actualPath');

    try {
      final file = io.File(actualPath);
      final raf = await file.open();
      final bytes = await raf.read(262144); // 256 KB
      await raf.close();
      debugPrint('[Eden][Scanner] Read ${bytes.length} bytes');

      // Search for <16-hex>.cnmt pattern in the raw bytes
      final content = String.fromCharCodes(bytes);
      final match = _cnmtRegex.firstMatch(content);

      if (match != null) {
        final raw = match.group(1)!;
        final normalized = _normalizeToBaseId(raw);
        debugPrint('[Eden][Scanner] Found: ${match.group(0)} → $normalized');
        return (normalized, actualPath);
      }

      debugPrint('[Eden][Scanner] No .cnmt match in first 256 KB');
    } catch (e) {
      debugPrint('[Eden][Scanner] ERROR: $e');
    }
    return (null, actualPath);
  }

  /// Force the last 3 hex chars to "000" → base game save folder.
  /// e.g. 0100704000B3A800 → 0100704000B3A000
  static String _normalizeToBaseId(String raw) {
    final upper = raw.toUpperCase();
    if (upper.length == 16) {
      return '${upper.substring(0, 13)}000';
    }
    return upper;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 2 — Profile ID Resolution
  // ═══════════════════════════════════════════════════════════════════════════

  /// Discovers the active Eden profile folder.
  ///
  /// Validation criteria: a profile is "active" only if it contains at least
  /// one Title ID subfolder that itself contains actual save data files
  /// (e.g. save.bin). This eliminates ghost/empty profiles.
  Future<String> _resolveProfileId(String baseSavePath) async {
    // 1. Manual override from conflict dialog
    if (_activeProfileOverride != null &&
        _activeProfileOverride!.isNotEmpty) {
      debugPrint('[Eden][Profile] Using override: $_activeProfileOverride');
      return _activeProfileOverride!;
    }

    // 2. Scan all 32-hex folders under .../save/0000000000000000/
    final zeroDir =
        io.Directory(p.join(baseSavePath, '0000000000000000'));
    if (!zeroDir.existsSync()) {
      throw Exception(
          'Eden save base does not exist: ${zeroDir.path}');
    }

    final candidates = <Map<String, dynamic>>[];

    for (final entity in zeroDir.listSync()) {
      if (entity is! io.Directory) continue;
      final name = p.basename(entity.path);
      if (!_profileRegex.hasMatch(name)) continue;

      // Find the newest *file* timestamp inside any Title ID subfolder.
      // Critical: we check FILE mtime, not directory mtime.
      // This kills the ghost profile bug.
      DateTime? newestFileTime;
      int saveFileCount = 0;

      for (final titleDir in entity.listSync()) {
        if (titleDir is! io.Directory) continue;
        final titleName = p.basename(titleDir.path);
        if (!titleName.startsWith('01') || titleName.length != 16) continue;

        try {
          for (final file in titleDir.listSync(recursive: true)) {
            if (file is! io.File) continue;
            final fname = p.basename(file.path);
            if (fname.startsWith('.') || fname.endsWith('.bak')) continue;

            saveFileCount++;
            final stat = file.statSync();
            if (newestFileTime == null ||
                stat.modified.isAfter(newestFileTime)) {
              newestFileTime = stat.modified;
            }
          }
        } catch (_) {
          // Permission errors, broken symlinks — skip
        }
      }

      // Only consider profiles that actually contain save files
      if (newestFileTime != null && saveFileCount > 0) {
        candidates.add({
          'id': name,
          'newestFile': newestFileTime,
          'fileCount': saveFileCount,
        });
      }
    }

    if (candidates.isEmpty) {
      throw Exception(
          'No active Eden profiles found in ${zeroDir.path}. '
          'Have you played any games in Eden yet?');
    }

    // Sort by newest save file activity
    candidates.sort((a, b) => (b['newestFile'] as DateTime)
        .compareTo(a['newestFile'] as DateTime));

    // Single candidate → done
    if (candidates.length == 1) {
      final id = candidates.first['id'] as String;
      debugPrint('[Eden][Profile] Single active profile: $id');
      return id;
    }

    // Multiple candidates: check if the winner is clearly ahead
    final winner = candidates[0];
    final runnerUp = candidates[1];
    final gap = (winner['newestFile'] as DateTime)
        .difference(runnerUp['newestFile'] as DateTime);

    // Auto-pick if >1h newer or runner-up has very few files (ghost)
    if (gap.inHours >= 1 ||
        (runnerUp['fileCount'] as int) <= 1) {
      final id = winner['id'] as String;
      debugPrint(
          '[Eden][Profile] Auto-selected: $id '
          '(gap: ${gap.inMinutes}m, '
          'runner-up files: ${runnerUp['fileCount']})');
      return id;
    }

    // Genuine conflict
    debugPrint(
        '[Eden][Profile] CONFLICT: ${candidates.map((c) => c['id']).join(', ')}');
    throw ProfileConflictException(candidates);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ROM file resolution (fuzzy matching)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Given a path that might be missing an extension, might be a directory,
  /// or might have a slightly different name than the actual file on disk,
  /// find the real ROM file.
  Future<String?> _resolveRomFile(String romPath) async {
    // Case 1: Exact path exists and is a file
    if (io.File(romPath).existsSync()) return romPath;

    // Case 2: Try appending known extensions
    for (final ext in _romExtensions) {
      final withExt = '$romPath$ext';
      if (io.File(withExt).existsSync()) {
        debugPrint('[Eden][Resolve] Extension fix: $withExt');
        return withExt;
      }
    }

    // Case 3: Path is a directory → find largest ROM inside
    if (io.Directory(romPath).existsSync()) {
      return _findLargestRomInDir(romPath);
    }

    // Case 4: Fuzzy search the parent directory
    final parentPath = p.dirname(romPath);
    final parentDir = io.Directory(parentPath);
    if (!parentDir.existsSync()) return null;

    final baseName = p.basenameWithoutExtension(romPath);
    final searchTokens = _tokenize(baseName);

    if (searchTokens.isEmpty) return null;

    io.File? bestMatch;
    int bestScore = 0;

    for (final entity in parentDir.listSync()) {
      if (entity is! io.File) continue;
      final fileName = p.basename(entity.path).toLowerCase();
      if (!_romExtensions.any((ext) => fileName.endsWith(ext))) continue;

      final fileTokens = _tokenize(p.basenameWithoutExtension(entity.path));
      int score = 0;
      for (final token in searchTokens) {
        if (fileTokens.contains(token)) score++;
      }

      // Require at least half the search tokens to match
      if (score > bestScore && score >= (searchTokens.length / 2).ceil()) {
        bestScore = score;
        bestMatch = entity;
      }
    }

    if (bestMatch != null) {
      debugPrint(
          '[Eden][Resolve] Fuzzy match: ${bestMatch.path} '
          '(score: $bestScore/${searchTokens.length})');
      return bestMatch.path;
    }

    // Case 4b: Fuzzy match DIRECTORIES in parent (multi-file ROMs)
    // e.g. path is ".../switch/Snipperclips Cut it out Together" but actual
    // dir is ".../switch/Snipperclips_ Cut It Out, Together!"
    for (final entity in parentDir.listSync()) {
      if (entity is! io.Directory) continue;
      final dirName = p.basename(entity.path);
      final dirTokens = _tokenize(dirName);
      int score = 0;
      for (final token in searchTokens) {
        if (dirTokens.contains(token)) score++;
      }
      if (score >= (searchTokens.length / 2).ceil() && score > 0) {
        final found = _findLargestRomInDir(entity.path);
        if (found != null) {
          debugPrint('[Eden][Resolve] Fuzzy dir match: ${entity.path} → $found');
          return found;
        }
      }
    }

    // Case 5: Try one level up (multi-file ROMs in sibling dirs)
    final grandparent = io.Directory(p.dirname(parentPath));
    if (grandparent.existsSync()) {
      for (final subDir in grandparent.listSync()) {
        if (subDir is! io.Directory) continue;
        final dirName = p.basename(subDir.path).toLowerCase();
        final dirTokens = _tokenize(dirName);
        int score = 0;
        for (final token in searchTokens) {
          if (dirTokens.contains(token)) score++;
        }
        if (score >= (searchTokens.length / 2).ceil()) {
          final found = _findLargestRomInDir(subDir.path);
          if (found != null) {
            debugPrint('[Eden][Resolve] Found in sibling dir: $found');
            return found;
          }
        }
      }
    }

    return null;
  }

  /// Find the largest .nsp/.xci/.nsz file in a directory tree.
  String? _findLargestRomInDir(String dirPath) {
    io.File? largest;
    int maxSize = -1;

    try {
      for (final entity
          in io.Directory(dirPath).listSync(recursive: true)) {
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

  /// Splits a filename into lowercase tokens for fuzzy comparison.
  /// "Snipperclips - Plus [0100704000B3A000]" → {snipperclips, plus}
  static Set<String> _tokenize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\[[^\]]*\]'), '') // strip [brackets]
        .replaceAll(RegExp(r'\([^)]*\)'), '') // strip (parens)
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ') // non-alphanum → space
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1) // drop single-char noise
        .toSet();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Platform-specific save base path
  // ═══════════════════════════════════════════════════════════════════════════

  String? _getEdenSaveBase() {
    if (io.Platform.isMacOS || io.Platform.isLinux) {
      final home = io.Platform.environment['HOME'];
      if (home == null) return null;
      return p.join(home, '.local', 'share', 'eden', 'nand', 'user', 'save');
    } else if (io.Platform.isWindows) {
      final appData = io.Platform.environment['APPDATA'];
      if (appData == null) return null;
      return p.join(appData, 'eden', 'nand', 'user', 'save');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Public API — SaveStrategy overrides
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    debugPrint('=== EDEN SAVE DIR: ${game.name} ===');

    final base = _getEdenSaveBase();
    if (base == null) {
      throw Exception('Cannot determine Eden save path on this platform.');
    }

    final profileId = await _resolveProfileId(base);
    final titleId = await _resolveTitleId(romPath, game);

    // Single 0000...00 layer, then profile, then title
    final finalPath =
        p.join(base, '0000000000000000', profileId, titleId);
    debugPrint('[Eden] Final path: $finalPath');

    if (io.Directory(finalPath).existsSync()) {
      return finalPath;
    }

    // Path doesn't exist yet — return it anyway.
    // pushSaves checks for files inside, pull creates the dir during restore.
    debugPrint('[Eden] Path does not exist on disk yet: $finalPath');
    return finalPath;
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
    final files = dir
        .listSync(recursive: true)
        .whereType<io.File>()
        .where((f) {
      final name = p.basename(f.path);
      return !name.startsWith('.') && !name.endsWith('.bak');
    }).toList();

    if (files.isEmpty) {
      if (syncMode == 'push') {
        throw Exception(
            'Save directory exists but contains no save files.');
      }
      return [];
    }

    // If sessionStart filter is set, check if any file was modified after it
    if (sessionStart != null) {
      final hasChanges = files.any(
          (f) => f.statSync().modified.isAfter(sessionStart));
      if (!hasChanges) {
        debugPrint('[Eden] No files modified since session start');
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
    String destPath, // This is the ROM path, passed through from pullSave
    Uint8List data,
    String filename,
  ) async {
    try {
      debugPrint('=== EDEN RESTORE: ${game.name} ===');

      final base = _getEdenSaveBase();
      if (base == null) return false;

      final profileId = await _resolveProfileId(base);

      // Resolve Title ID using the ROM path (destPath = romPath from pullSave)
      String? titleId;

      // 1. Header scan on the ROM
      final (headerId, resolvedPath) = await extractTitleIdFromHeader(destPath);
      titleId = headerId;
      if (titleId != null) {
        debugPrint('[Eden][Restore] Title ID from header: $titleId');
      }

      // 2. Filename extraction
      if (titleId == null) {
        titleId = _extractTitleIdFromFilename(resolvedPath ?? destPath, game);
        if (titleId != null) {
          debugPrint('[Eden][Restore] Title ID from filename: $titleId');
        }
      }

      // 3. Check inside ZIP entries for Title ID folder names
      Archive? archive;
      if (titleId == null && filename.toLowerCase().endsWith('.zip')) {
        archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          final match = _titleIdExtractorRegex.firstMatch(entry.name);
          if (match != null) {
            titleId = _normalizeToBaseId(match.group(0)!);
            debugPrint('[Eden][Restore] Title ID from ZIP entry: $titleId');
            break;
          }
        }
      }

      // 4. Manual mapping
      if (titleId == null &&
          _manualMapping != null &&
          _manualMapping!.isNotEmpty) {
        titleId = _manualMapping;
        debugPrint('[Eden][Restore] Title ID from manual mapping: $titleId');
      }

      // 5. Give up
      if (titleId == null) {
        debugPrint('[Eden][Restore] FAILED: No Title ID resolved');
        throw SaveMappingRequiredException();
      }

      // Construct target and create if needed
      final targetPath =
          p.join(base, '0000000000000000', profileId, titleId);
      debugPrint('[Eden][Restore] Target: $targetPath');
      io.Directory(targetPath).createSync(recursive: true);

      // Extract or write
      if (filename.toLowerCase().endsWith('.zip')) {
        archive ??= ZipDecoder().decodeBytes(data);
        return await _extractArchive(archive, targetPath);
      } else {
        final filePath = p.join(targetPath, filename);
        await backupSave(filePath);
        await io.File(filePath).writeAsBytes(data);
        debugPrint('[Eden][Restore] Wrote single file: $filePath');
        return true;
      }
    } catch (e) {
      if (e is SaveMappingRequiredException ||
          e is ProfileConflictException) {
        rethrow;
      }
      debugPrint('[Eden][Restore] ERROR: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Lists all Title ID save folders for the active profile.
  /// Used by the UI for manual folder selection.
  Future<List<Map<String, dynamic>>> getAvailableSaveFolders() async {
    final base = _getEdenSaveBase();
    if (base == null) return [];

    String profileId;
    try {
      profileId = await _resolveProfileId(base);
    } catch (_) {
      return [];
    }

    final profileDir =
        io.Directory(p.join(base, '0000000000000000', profileId));
    if (!profileDir.existsSync()) return [];

    final folders = <Map<String, dynamic>>[];
    for (final entity in profileDir.listSync()) {
      if (entity is! io.Directory) continue;
      final name = p.basename(entity.path);
      if (!_strictTitleIdRegex.hasMatch(name)) continue;

      DateTime? newest;
      int fileCount = 0;
      for (final f in entity.listSync(recursive: true)) {
        if (f is! io.File) continue;
        fileCount++;
        final mod = f.statSync().modified;
        if (newest == null || mod.isAfter(newest)) newest = mod;
      }

      if (fileCount > 0) {
        folders.add({
          'name': name,
          'lastModified': newest,
          'fileCount': fileCount,
        });
      }
    }

    folders.sort((a, b) => (b['lastModified'] as DateTime)
        .compareTo(a['lastModified'] as DateTime));
    return folders;
  }

  /// Extracts a ZIP archive into [destDir], stripping a leading Title ID
  /// folder if present (so the save files land directly in the target).
  Future<bool> _extractArchive(Archive archive, String destDir) async {
    try {
      for (final entry in archive) {
        if (entry.name.isEmpty) continue;

        // Strip leading Title ID folder from path if present.
        // e.g. "0100704000B3A000/save.bin" → "save.bin"
        final segments = entry.name.split(RegExp(r'[/\\]'));
        final entryPath = (segments.length > 1 &&
                _strictTitleIdRegex.hasMatch(segments.first))
            ? p.joinAll(segments.sublist(1))
            : entry.name;

        if (entryPath.isEmpty) continue;

        final outPath = p.join(destDir, entryPath);
        if (entry.isFile) {
          await backupSave(outPath);
          final outFile = io.File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
          debugPrint('[Eden][Extract] ${entry.name} → $outPath');
        } else {
          await io.Directory(outPath).create(recursive: true);
        }
      }
      return true;
    } catch (e) {
      debugPrint('[Eden][Extract] ERROR: $e');
      return false;
    }
  }
}
