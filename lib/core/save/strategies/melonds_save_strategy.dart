import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import '../../platform/platform_info.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for melonDS (Nintendo DS).
///
/// Checks the RetroArch save directory as fallback for users running
/// RetroArch with the melonDS / DeSmuME core.
class MelonDsSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;
  final PlatformInfo _platform;
  String? _cachedRetroarchDir;

  MelonDsSaveStrategy(this._directoryService, {PlatformInfo? platform})
      : _platform = platform ?? PlatformInfo.current;

  @override
  String get strategyId => 'melonds';

  @override
  bool get shouldZip => false;

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    debugPrint('[SaveSync] [melonDS] getSaveDir: romPath=$romPath');

    if (_platform.isLinux) {
      final emuDir = await _directoryService.getEmulatorAppSupportDirectory('melonds');
      if (await io.Directory(emuDir).exists()) {
        debugPrint('[SaveSync] [melonDS]   → Linux melonDS dir: $emuDir');
        return emuDir;
      }
      debugPrint('[SaveSync] [melonDS]   Linux melonDS dir not found: $emuDir');
      // Also check the RetroArch save dir on Linux
      _cachedRetroarchDir ??= await SaveStrategy.retroarchCoreSaveDir(_directoryService, 'NDS', platform: _platform);
      if (_cachedRetroarchDir != null && await io.Directory(_cachedRetroarchDir!).exists()) {
        debugPrint('[SaveSync] [melonDS]   → Linux RetroArch fallback: $_cachedRetroarchDir');
        return _cachedRetroarchDir;
      }
    }

    final romDir = io.File(romPath).parent.path;

    // 1. ROM-adjacent (standalone melonDS default on Windows/macOS)
    if (await io.Directory(romDir).exists()) {
      final stem = p.basenameWithoutExtension(romPath).toLowerCase();
      final dir = io.Directory(romDir);
      await for (final entity in dir.list()) {
        if (entity is io.File) {
          final fname = p.basename(entity.path).toLowerCase();
          if (fname == '$stem.sav' || fname == '$stem.srm') {
            debugPrint('[SaveSync] [melonDS]   → ROM-adjacent match: $fname in $romDir');
            return romDir;
          }
        }
      }
    }

    // 2. %APPDATA%\melonDS on Windows
    if (_platform.isWindows) {
      final appData = _platform.environment['APPDATA'] ?? '';
      if (appData.isNotEmpty) {
        for (final folderName in ['melonDS', 'melonds']) {
          final melonDir = io.Directory(p.join(appData, folderName));
          if (await melonDir.exists()) {
            debugPrint('[SaveSync] [melonDS]   → Windows APPDATA: ${melonDir.path}');
            return melonDir.path;
          }
        }
      }
      final userProfile = _platform.environment['USERPROFILE'] ?? '';
      if (userProfile.isNotEmpty) {
        final docsDir = io.Directory(p.join(userProfile, 'Documents', 'melonDS'));
        if (await docsDir.exists()) {
          debugPrint('[SaveSync] [melonDS]   → Windows Documents: ${docsDir.path}');
          return docsDir.path;
        }
      }
    }

    // 3. macOS: ~/Library/Application Support/melonDS
    if (_platform.isMacOS) {
      final home = _platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) {
        final macDir = io.Directory(p.join(home, 'Library', 'Application Support', 'melonDS'));
        if (await macDir.exists()) {
          debugPrint('[SaveSync] [melonDS]   → macOS App Support: ${macDir.path}');
          return macDir.path;
        }
      }
    }

    // 4. Fallback: RetroArch melonDS/DeSmuME core save directory
    _cachedRetroarchDir ??= await SaveStrategy.retroarchCoreSaveDir(_directoryService, 'NDS', platform: _platform);
    if (_cachedRetroarchDir != null) {
      debugPrint('[SaveSync] [melonDS]   → RetroArch core fallback: $_cachedRetroarchDir');
      return _cachedRetroarchDir;
    }

    // 5. Absolute fallback
    debugPrint('[SaveSync] [melonDS]   → absolute fallback: $romDir (ROM directory)');
    return romDir;
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) {
      debugPrint('[SaveSync] [melonDS] getSaveFiles: no save dir found');
      return [];
    }

    final romStem = p.basenameWithoutExtension(romPath).toLowerCase();
    final fallbackStem = getRomStem(game).toLowerCase();
    final stemWords = romStem
        .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
        .split(' ')
        .where((w) => w.length >= 3)
        .toList();

    debugPrint('[SaveSync] [melonDS] getSaveFiles: searching in $saveDir');
    debugPrint('[SaveSync] [melonDS]   looking for: $romStem.sav / $romStem.srm (or $fallbackStem.*)');

    final dir = io.Directory(saveDir);
    if (!await dir.exists()) {
      debugPrint('[SaveSync] [melonDS]   save dir does not exist');
      return [];
    }

    // Exact match
    final List<io.File> foundFiles = [];
    await for (final entity in dir.list()) {
      if (entity is! io.File) continue;
      final fname = p.basename(entity.path).toLowerCase();
      if ((fname == '$romStem.sav' || fname == '$fallbackStem.sav' || fname == '$romStem.srm' || fname == '$fallbackStem.srm')) {
        if (sessionStart != null) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) {
            debugPrint('[SaveSync] [melonDS]   skip (before sessionStart): $fname');
            continue;
          }
        }
        debugPrint('[SaveSync] [melonDS]   → exact match: ${entity.path}');
        foundFiles.add(entity);
        break;
      }
    }

    // Fuzzy fallback: match by word tokens
    if (foundFiles.isEmpty && stemWords.isNotEmpty) {
      debugPrint('[SaveSync] [melonDS]   no exact match, trying fuzzy: $stemWords');
      await for (final entity in dir.list()) {
        if (entity is! io.File) continue;
        final fname = p.basename(entity.path).toLowerCase();
        if (!fname.endsWith('.srm') && !fname.endsWith('.sav')) continue;
        if (stemWords.any((word) => fname.contains(word))) {
          if (sessionStart != null) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
          }
          debugPrint('[SaveSync] [melonDS]   → fuzzy match: ${entity.path}');
          foundFiles.add(entity);
          break;
        }
      }
    }

    if (foundFiles.isEmpty) {
      debugPrint('[SaveSync] [melonDS]   no save files found in $saveDir');
    }
    return foundFiles;
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) {
        debugPrint('[SaveSync] [melonDS] restoreSave: no save dir');
        return false;
      }

      final romStem = p.basenameWithoutExtension(destPath).toLowerCase();
      final fallbackStem = getRomStem(game).toLowerCase();
      String targetPath = p.normalize(p.join(saveDir, '$romStem.sav'));
      debugPrint('[SaveSync] [melonDS] restoreSave: filename=$filename  targetDir=$saveDir');

      if (filename.toLowerCase().endsWith('.zip')) {
        debugPrint('[SaveSync] [melonDS]   extracting ZIP...');
        final archive = ZipDecoder().decodeBytes(data);
        for (final file in archive) {
          if (!file.isFile) continue;
          if (file.name == 'freegosy_sync.txt') continue;
          if (file.name.toLowerCase().endsWith('.sav')) {
            debugPrint('[SaveSync] [melonDS]   → extracted ${file.name} → $targetPath');
            await io.Directory(p.dirname(targetPath)).create(recursive: true);
            await backupSave(targetPath);
            await io.File(targetPath).writeAsBytes(file.content);
            return true;
          }
        }
        debugPrint('[SaveSync] [melonDS]   ZIP contained no .sav files');
        return true;
      }

      final dir = io.Directory(saveDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is! io.File) continue;
          final fname = p.basename(entity.path).toLowerCase();
          if (fname == '$romStem.sav' || fname == '$fallbackStem.sav' || fname == '$romStem.srm' || fname == '$fallbackStem.srm') {
            targetPath = entity.path;
            debugPrint('[SaveSync] [melonDS]   → found existing save: $targetPath');
            break;
          }
        }
        // Fuzzy fallback if strict match failed
        if (targetPath == p.normalize(p.join(saveDir, '$romStem.sav'))) {
          final stemWords = romStem
              .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
              .split(' ')
              .where((w) => w.length >= 3)
              .toList();
          if (stemWords.isNotEmpty) {
            await for (final entity in dir.list()) {
              if (entity is! io.File) continue;
              final fname = p.basename(entity.path).toLowerCase();
              if (!fname.endsWith('.srm') && !fname.endsWith('.sav')) continue;
              if (stemWords.any((word) => fname.contains(word))) {
                targetPath = entity.path;
                debugPrint('[SaveSync] [melonDS]   → fuzzy match existing: $targetPath');
                break;
              }
            }
          }
        }
      }

      debugPrint('[SaveSync] [melonDS]   writing ${data.length} bytes → $targetPath');
      await io.Directory(p.dirname(targetPath)).create(recursive: true);
      await backupSave(targetPath);
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      debugPrint('[SaveSync] [melonDS] restoreSave ERROR: $e');
      return false;
    }
  }
}
