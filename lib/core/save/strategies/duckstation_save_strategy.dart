import 'dart:io';
import 'dart:io' as io;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../platform/platform_info.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for DuckStation (PlayStation 1).
class DuckstationSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;
  final PlatformInfo _platform;

  DuckstationSaveStrategy(this._directoryService, {PlatformInfo? platform})
      : _platform = platform ?? PlatformInfo.current;

  @override
  String get strategyId => 'duckstation';

  String _getEmuExe() {
    if (_platform.isWindows) return 'duckstation-qt-x64-ReleaseLTCG.exe';
    if (_platform.isMacOS) return 'DuckStation.app/Contents/MacOS/DuckStation';
    return 'duckstation-qt';
  }

  Future<String> _getBaseDir({String? platformSlug}) async {
    // 1. Check portable mode first (Windows)
    final exePath = await _directoryService.findEmulatorExecutable(
        'duckstation', _getEmuExe());
    if (exePath != null) {
      String emulatorDir = File(exePath).parent.path;
      if (_platform.isMacOS && exePath.contains('.app/Contents/MacOS/')) {
        emulatorDir = io.File(exePath).parent.parent.parent.parent.path;
      }
      if (await File(p.join(emulatorDir, 'portable.txt')).exists()) {
        return emulatorDir;
      }
    }

    // 2. Dynamic path resolution for macOS/Windows/Linux
    final String resolvedPath;
    if (_platform.isWindows) {
      final localAppData = _platform.environment['LOCALAPPDATA'] ?? '';
      resolvedPath = p.join(localAppData, 'DuckStation');
    } else {
      resolvedPath = await _directoryService.getEmulatorAppSupportDirectory('DuckStation', platformSlug: platformSlug);
    }

    if (!await io.Directory(resolvedPath).exists()) {
      throw Exception('Save directory not found for DuckStation at $resolvedPath. Please launch DuckStation at least once to generate save data.');
    }
    return resolvedPath;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final baseDir = await _getBaseDir(platformSlug: game.platformSlug);
    return p.join(baseDir, 'memcards');
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final baseDir = await _getBaseDir(platformSlug: game.platformSlug);
    debugPrint('[DuckStation] Save base: $baseDir');

    final result = <File>[];
    final stem = getRomStem(game);
    // Normalize the stem so multi-disc .m3u filenames like
    // "Final Fantasy VII (USA).m3u" match the bare save title card
    // "Final Fantasy VII_1.mcd" (issue #62).
    final cleanStem = normalizeSaveMatchName(stem).toLowerCase();
    debugPrint('[DuckStation] ROM stem: $stem  cleanStem: $cleanStem  sessionStart=$sessionStart');

    final memcardsDir = Directory(p.join(baseDir, 'memcards'));
    if (await memcardsDir.exists()) {
      // Layer 1: per-game .mcd. DuckStation's per-game cards are named
      // `{title}_N.mcd` (PerGameTitle) or `{serial}_N.mcd` (PerGame) with a
      // slot-number suffix. We match by normalized stem as a substring, which
      // covers both (e.g. "Suikoden II_1.mcd" contains "Suikoden II"). Keep
      // only the newest matching card to avoid uploading multiple saves.
      File? bestMcd;
      DateTime? bestMcdMtime;
      await for (final entity in memcardsDir.list()) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.mcd')) continue;
        final base = p.basename(entity.path).toLowerCase();
        // Shared cards (shared_card_N.mcd) are handled in Layer 2 — never
        // treat them as a per-game match here.
        if (base.startsWith('shared_card_')) continue;
        // Strip the `_N` slot suffix and any tags from the card name before
        // comparing, so "suikoden ii_1" matches cleanStem "suikoden ii".
        final cardName = base.substring(0, base.length - 4); // drop ".mcd"
        final cleanCard = normalizeSaveMatchName(
                cardName.replaceAll(RegExp(r'_\d+$'), ''))
            .toLowerCase();

        // Word-token match: split the stem into tokens (>=3 chars) and require
        // every token to appear in the card. This avoids substring false
        // positives like "final fantasy vii" matching "final fantasy viii".
        final stemTokens = cleanStem
            .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
            .split(' ')
            .where((w) => w.length >= 3)
            .toList();
        final cardTokens = cleanCard
            .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
            .split(' ')
            .where((w) => w.isNotEmpty)
            .toList();
        final matches = stemTokens.isNotEmpty &&
            stemTokens.every((w) => cardTokens.contains(w));
        if (!matches) {
          debugPrint('[DuckStation]   skipping (no stem match): ${entity.path}');
          continue;
        }
        final stat = await entity.stat();
        if (sessionStart != null &&
            stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
        if (bestMcd == null || stat.modified.isAfter(bestMcdMtime!)) {
          bestMcd = entity;
          bestMcdMtime = stat.modified;
        }
      }
      if (bestMcd != null) {
        debugPrint('[DuckStation]   per-game memcard found: ${bestMcd.path}');
        result.add(bestMcd);
      }

      // Layer 2: fall back to shared memory cards. DuckStation's real shared
      // cards are `shared_card_1.mcd` / `shared_card_2.mcd`. We also accept the
      // legacy `Mcd001.mcd` style used by older builds/forks. Upload all shared
      // cards so the slot the game actually wrote to is covered.
      if (result.isEmpty) {
        final shared = <File>[];
        await for (final entity in memcardsDir.list()) {
          if (entity is! File) continue;
          final base = p.basename(entity.path).toLowerCase();
          final isRealShared = base.startsWith('shared_card_') && base.endsWith('.mcd');
          final isLegacyShared = RegExp(r'^mcd\d+\.mcd$').hasMatch(base);
          if (!isRealShared && !isLegacyShared) continue;
          if (sessionStart != null) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
          }
          shared.add(entity);
        }
        if (shared.isNotEmpty) {
          debugPrint('[DuckStation]   using shared memcards: ${shared.map((f) => f.path).toList()}');
          result.addAll(shared);
        }
      }
    } else {
      debugPrint('[DuckStation]   memcards dir missing: ${memcardsDir.path}');
    }

    final statesDir = Directory(p.join(baseDir, 'savestates'));
    if (await statesDir.exists()) {
      await for (final entity in statesDir.list()) {
        if (entity is File && p.basename(entity.path).toLowerCase().contains(stem.toLowerCase())) {
          if (sessionStart != null) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
          }
          result.add(entity);
        }
      }
    }

    return result;
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final baseDir = await _getBaseDir(platformSlug: game.platformSlug);

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          if (!entry.isFile) continue;
          final entryLower = entry.name.toLowerCase();
          final targetDirName = entryLower.endsWith('.mcd')
              ? 'memcards'
              : 'savestates';
          final targetDir = p.join(baseDir, targetDirName);

          final targetPath = p.normalize(p.join(targetDir, p.basename(entry.name)));
          await backupSave(targetPath);
          final outFile = File(targetPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
        }
        return true;
      }

      final isState = !filename.toLowerCase().endsWith('.mcd');
      final targetDirName = isState ? 'savestates' : 'memcards';
      final targetPath = p.normalize(p.join(baseDir, targetDirName, filename));
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}
