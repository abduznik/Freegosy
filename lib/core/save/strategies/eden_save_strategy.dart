import 'dart:io' as io;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../../storage/rom_lookup_service.dart';
import '../save_strategy.dart';

class ProfileConflictException implements Exception {
  final List<Map<String, dynamic>> profiles;
  ProfileConflictException(this.profiles);
  @override
  String toString() => 'ProfileConflictException: ${profiles.length} active profiles found.';
}

/// Save strategy for Eden (Switch) emulator.
class EdenSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;
  final Future<void> Function(String gameId, String titleId)? onMappingResolved;

  EdenSaveStrategy(this._directoryService, {this.onMappingResolved});

  @override
  String get strategyId => 'switch';
  @override
  bool get supportsSaveSync => true;

  static final RegExp _titleIdExtractorRegex = RegExp(r'01[0-9A-Fa-f]{14}');
  static final RegExp _cnmtRegex = RegExp(r'(01[0-9A-Fa-f]{14})\.cnmt', caseSensitive: false);
  static final RegExp _profileRegex = RegExp(r'^[0-9A-Fa-f]{32}$');
  static const _romExtensions = ['.nsp', '.xci', '.nsz'];

  String? _manualMapping;
  String? _activeProfileOverride;

  void setManualMapping(String? titleId) => _manualMapping = titleId;
  void setActiveProfileOverride(String? profileId) => _activeProfileOverride = profileId;

  Future<String> _resolveTitleId(String romPath, Game game) async {
    final (fromHeader, resolvedRomPath) = await extractTitleIdFromHeader(romPath);
    if (fromHeader != null) {
      if (onMappingResolved != null) await onMappingResolved!(game.id, fromHeader);
      return fromHeader;
    }

    final fromFilename = _extractTitleIdFromFilename(resolvedRomPath ?? romPath, game);
    if (fromFilename != null) {
      if (onMappingResolved != null) await onMappingResolved!(game.id, fromFilename);
      return fromFilename;
    }

    if (_manualMapping != null && _manualMapping!.isNotEmpty) return _manualMapping!;

    throw SaveMappingRequiredException('Could not determine Title ID for "${game.name}". Please select the save folder manually.');
  }

  String? _extractTitleIdFromFilename(String romPath, Game game) {
    for (final candidate in [p.basename(romPath), game.fileName ?? '', game.name]) {
      if (candidate.isEmpty) continue;
      final match = _titleIdExtractorRegex.firstMatch(candidate);
      if (match != null) return _normalizeToBaseId(match.group(0)!);
    }
    return null;
  }

  Future<(String? titleId, String? resolvedPath)> extractTitleIdFromHeader(String romPath) async {
    final actualPath = await RomLookupService.resolveFuzzyRomFile(romPath, _romExtensions);
    if (actualPath == null) return (null, null);

    try {
      final file = io.File(actualPath);
      final raf = await file.open();
      final bytes = await raf.read(262144); // 256 KB
      await raf.close();
      final content = String.fromCharCodes(bytes);
      final match = _cnmtRegex.firstMatch(content);
      if (match != null) return (_normalizeToBaseId(match.group(1)!), actualPath);
    } catch (_) {}
    return (null, actualPath);
  }

  static String _normalizeToBaseId(String raw) {
    final upper = raw.toUpperCase();
    return upper.length == 16 ? '${upper.substring(0, 13)}000' : upper;
  }

  Future<String> _resolveProfileId(String baseSavePath) async {
    if (_activeProfileOverride != null && _activeProfileOverride!.isNotEmpty) return _activeProfileOverride!;
    final zeroDir = io.Directory(p.join(baseSavePath, '0000000000000000'));
    if (!zeroDir.existsSync()) throw Exception('Eden save base does not exist: ${zeroDir.path}');

    final candidates = <Map<String, dynamic>>[];
    for (final entity in zeroDir.listSync()) {
      if (entity is! io.Directory) continue;
      final name = p.basename(entity.path);
      if (!_profileRegex.hasMatch(name)) continue;

      DateTime? newestFileTime;
      int saveFileCount = 0;
      for (final titleDir in entity.listSync()) {
        if (titleDir is! io.Directory) continue;
        try {
          for (final file in titleDir.listSync(recursive: true)) {
            if (file is! io.File || p.basename(file.path).startsWith('.') || p.basename(file.path).endsWith('.bak')) continue;
            saveFileCount++;
            final mtime = file.statSync().modified;
            if (newestFileTime == null || mtime.isAfter(newestFileTime)) newestFileTime = mtime;
          }
        } catch (_) {}
      }
      if (newestFileTime != null && saveFileCount > 0) candidates.add({'id': name, 'newestFile': newestFileTime, 'fileCount': saveFileCount});
    }

    if (candidates.isEmpty) throw Exception('No active Eden profiles found.');
    candidates.sort((a, b) => (b['newestFile'] as DateTime).compareTo(a['newestFile'] as DateTime));
    if (candidates.length == 1) return candidates.first['id'] as String;

    final winner = candidates[0];
    final runnerUp = candidates[1];
    final gap = (winner['newestFile'] as DateTime).difference(runnerUp['newestFile'] as DateTime);
    if (gap.inHours >= 1 || (runnerUp['fileCount'] as int) <= 1) return winner['id'] as String;
    throw ProfileConflictException(candidates);
  }

  Future<String> _getEdenSaveBase({String? platformSlug}) async {
    final String resolvedPath;
    if (io.Platform.isMacOS || io.Platform.isLinux) {
      resolvedPath = await _directoryService.getEmulatorAppSupportDirectory('eden', platformSlug: platformSlug);
    } else if (io.Platform.isWindows) {
      resolvedPath = p.join(io.Platform.environment['APPDATA'] ?? '', 'eden');
    } else {
      throw UnsupportedError('Platform not supported');
    }
    final finalPath = p.join(resolvedPath, 'nand', 'user', 'save');
    if (!await io.Directory(finalPath).exists()) throw Exception('Save directory not found for Eden.');
    return finalPath;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final base = await _getEdenSaveBase(platformSlug: game.platformSlug);
    final profileId = await _resolveProfileId(base);
    final titleId = await _resolveTitleId(romPath, game);
    return p.join(base, '0000000000000000', profileId, titleId);
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];
    final dir = io.Directory(saveDir);
    if (!dir.existsSync()) {
      if (syncMode == 'push') throw Exception('Local save data not found.');
      return [];
    }
    final files = dir.listSync(recursive: true).whereType<io.File>().where((f) {
      final name = p.basename(f.path);
      return !name.startsWith('.') && !name.endsWith('.bak');
    }).toList();
    if (files.isEmpty && syncMode == 'push') throw Exception('No save files found.');
    if (sessionStart != null && !files.any((f) => f.statSync().modified.isAfter(sessionStart))) return [];
    return [io.File(saveDir)];
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    final base = await _getEdenSaveBase(platformSlug: game.platformSlug);
    final profileId = await _resolveProfileId(base);
    String? titleId;
    final (headerId, resolvedPath) = await extractTitleIdFromHeader(destPath);
    titleId = headerId ?? _extractTitleIdFromFilename(resolvedPath ?? destPath, game);

    Archive? archive;
    if (titleId == null && filename.toLowerCase().endsWith('.zip')) {
      archive = ZipDecoder().decodeBytes(data);
      for (final entry in archive) {
        final match = _titleIdExtractorRegex.firstMatch(entry.name);
        if (match != null) { titleId = _normalizeToBaseId(match.group(0)!); break; }
      }
    }
    titleId ??= _manualMapping;
    if (titleId == null) throw SaveMappingRequiredException();

    final targetPath = p.normalize(p.join(base, '0000000000000000', profileId, titleId));
    io.Directory(targetPath).createSync(recursive: true);

    if (filename.toLowerCase().endsWith('.zip')) {
      archive ??= ZipDecoder().decodeBytes(data);
      return await _extractArchive(archive, targetPath);
    } else {
      final filePath = p.normalize(p.join(targetPath, filename));
      await backupSave(filePath);
      await io.File(filePath).writeAsBytes(data);
      return true;
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableSaveFolders() async {
    final base = await _getEdenSaveBase();
    final profileId = await _resolveProfileId(base);
    final profileDir = io.Directory(p.join(base, '0000000000000000', profileId));
    if (!profileDir.existsSync()) return [];

    final folders = <Map<String, dynamic>>[];
    for (final entity in profileDir.listSync()) {
      if (entity is! io.Directory || !RegExp(r'^01[0-9A-Fa-f]{14}$').hasMatch(p.basename(entity.path))) continue;
      DateTime? newest;
      int count = 0;
      for (final f in entity.listSync(recursive: true)) {
        if (f is! io.File) continue;
        count++;
        final mod = f.statSync().modified;
        if (newest == null || mod.isAfter(newest)) newest = mod;
      }
      if (count > 0) folders.add({'name': p.basename(entity.path), 'lastModified': newest, 'fileCount': count});
    }
    folders.sort((a, b) => (b['lastModified'] as DateTime).compareTo(a['lastModified'] as DateTime));
    return folders;
  }

  Future<bool> _extractArchive(Archive archive, String destDir) async {
    try {
      final tidRegex = RegExp(r'^01[0-9A-Fa-f]{14}$');
      for (final entry in archive) {
        if (entry.name.isEmpty || entry.name == 'freegosy_sync.txt' || entry.name.contains('.bak')) continue;
        final segments = entry.name.split(RegExp(r'[/\\]'));
        final first = segments.first;
        final entryPath = (segments.length > 1 && (tidRegex.hasMatch(first) || RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(first) || RegExp(r'^\d+$').hasMatch(first)))
            ? p.joinAll(segments.sublist(1)) : entry.name;
        if (entryPath.isEmpty) continue;
        final outPath = p.normalize(p.join(destDir, entryPath));
        if (entry.isFile) {
          await backupSave(outPath);
          final outFile = io.File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
        } else { await io.Directory(outPath).create(recursive: true); }
      }
      return true;
    } catch (_) { rethrow; }
  }
}
