import 'dart:convert';
import 'dart:io' as io;
import 'dart:io' show File;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for PPSSPP (PSP).
class PpssppSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  PpssppSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'ppsspp';

  String _getEmuExe() {
    if (io.Platform.isWindows) return 'PPSSPPWindows64.exe';
    if (io.Platform.isMacOS) return 'PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL';
    return 'PPSSPPSDL';
  }

  Future<String> _getPspDir({String? platformSlug}) async {
    // 1. Check portable mode first (Windows)
    if (io.Platform.isWindows) {
      final exePath = await _directoryService.findEmulatorExecutable(
          'ppsspp', _getEmuExe());
      if (exePath != null) {
        final emuDir = io.File(exePath).parent.path;
        final portableDir = p.join(emuDir, 'memstick', 'PSP');
        if (await io.Directory(portableDir).exists()) {
          return portableDir;
        }
      }

      // 1b. Check Documents/PPSSPP/PSP (Windows default)
      final userProfile = io.Platform.environment['USERPROFILE'] ?? '';
      if (userProfile.isNotEmpty) {
        final docsPsp = p.join(userProfile, 'Documents', 'PPSSPP', 'PSP');
        if (await io.Directory(docsPsp).exists()) {
          return docsPsp;
        }
      }
    }

    // 2. Dynamic path resolution (favors EmuDeck if configured)
    final baseDir = await _directoryService.getEmulatorAppSupportDirectory('ppsspp', platformSlug: platformSlug);
    
    // Check if baseDir is a symlink (typical for EmuDeck)
    String resolvedBase = baseDir;
    try {
      if (await io.FileSystemEntity.isLink(baseDir)) {
        resolvedBase = await io.Link(baseDir).resolveSymbolicLinks();
      }
    } catch (_) {}

    // On Steam Deck, 'saves' symlink points to .../PSP/SAVEDATA.
    // If we resolved it, the PSP root is the parent.
    if (resolvedBase.toUpperCase().endsWith('SAVEDATA')) {
       return p.dirname(resolvedBase);
    }
    
    // Standard folder logic
    if (!resolvedBase.endsWith('PSP')) {
       final pspDir = p.join(resolvedBase, 'PSP');
       if (await io.Directory(pspDir).exists()) return pspDir;
    }

    return resolvedBase;
  }

  /// Reads PARAM.SFO file and extracts the game title.
  Future<String?> _readParamSfoTitle(String folderPath) async {
    try {
      final sfoFile = io.File(p.join(folderPath, 'PARAM.SFO'));
      if (!await sfoFile.exists()) return null;

      final bytes = await sfoFile.readAsBytes();
      if (bytes.length < 20) return null;
      final byteData = ByteData.view(bytes.buffer);

      if (bytes[0] != 0x00 || bytes[1] != 0x50 || bytes[2] != 0x53 || bytes[3] != 0x46) return null;

      final keyTableOffset  = byteData.getUint32(8,  Endian.little);
      final dataTableOffset = byteData.getUint32(12, Endian.little);
      final entriesCount    = byteData.getUint32(16, Endian.little);

      for (int i = 0; i < entriesCount; i++) {
        final entryBase = 20 + i * 16;
        if (entryBase + 16 > bytes.length) break;
        final keyRelOffset  = byteData.getUint16(entryBase + 0,  Endian.little);
        final dataLen       = byteData.getUint32(entryBase + 4,  Endian.little);
        final dataRelOffset = byteData.getUint32(entryBase + 12, Endian.little);

        final keyStart = keyTableOffset + keyRelOffset;
        final keyBytes = <int>[];
        int j = keyStart;
        while (j < bytes.length && bytes[j] != 0) {
          keyBytes.add(bytes[j++]);
        }
        final key = utf8.decode(keyBytes);

        if (key == 'TITLE') {
          final valueStart = dataTableOffset + dataRelOffset;
          final titleBytes = bytes.sublist(valueStart, valueStart + dataLen);
          final nullIdx = titleBytes.indexOf(0);
          return utf8.decode(nullIdx != -1 ? titleBytes.sublist(0, nullIdx) : titleBytes);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final pspDir = await _getPspDir(platformSlug: game.platformSlug);
    return p.join(pspDir, 'SAVEDATA');
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final pspDir = await _getPspDir(platformSlug: game.platformSlug);
    final result = <File>[];

    final saveDataDir = io.Directory(p.join(pspDir, 'SAVEDATA'));
    if (await saveDataDir.exists()) {
      final allSubdirs = await saveDataDir.list().where((e) => e is io.Directory).cast<io.Directory>().toList();
      final foldersWithTitles = <Map<String, dynamic>>[];
      for (final dir in allSubdirs) {
        final title = await _readParamSfoTitle(dir.path);
        if (title != null) {
          foldersWithTitles.add({'dir': dir, 'title': title, 'modified': (await dir.stat()).modified});
        }
      }

      final gameWords = game.name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9\s]"), '').split(' ').where((w) => w.length >= 2).toList();
      final matchingFolders = foldersWithTitles.where((entry) => gameWords.any((word) => (entry['title'] as String).toLowerCase().contains(word))).toList();

      List<io.Directory> foldersToBundle = [];
      if (matchingFolders.isNotEmpty) {
        foldersToBundle.addAll(matchingFolders.map((e) => e['dir'] as io.Directory));
      } else if (foldersWithTitles.isNotEmpty) {
        foldersWithTitles.sort((a, b) => (b['modified'] as DateTime).compareTo(a['modified'] as DateTime));
        foldersToBundle.add(foldersWithTitles.first['dir'] as io.Directory);
      }

      for (final dir in foldersToBundle) {
        result.add(io.File(dir.path));
      }
    }

    final statesDir = io.Directory(p.join(pspDir, 'PPSSPP_STATE'));
    if (await statesDir.exists()) {
      final stemLower = getRomStem(game).toLowerCase();
      await for (final entity in statesDir.list()) {
        if (entity is! io.File) continue;
        final fname = p.basename(entity.path).toLowerCase();
        if (fname == '$stemLower.ppst') {
          if (sessionStart == null || (await entity.stat()).modified.isAfter(sessionStart)) {
            result.add(entity);
          }
          break;
        }
      }
    }

    return result;
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final pspDir = await _getPspDir(platformSlug: game.platformSlug);
      final targetSaveDir = p.join(pspDir, 'SAVEDATA');
      final targetStateDir = p.join(pspDir, 'PPSSPP_STATE');

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        await io.Directory(targetSaveDir).create(recursive: true);
        await io.Directory(targetStateDir).create(recursive: true);

        for (final entry in archive) {
          if (entry.name.contains('.bak') || entry.name == 'freegosy_sync.txt') continue;
          
          // SMART FLATTENING: Strip redundant psp/PSP/SAVEDATA prefixes
          String cleanName = entry.name.replaceAll('\\', '/');
          final parts = cleanName.split('/');
          
          // If the ZIP contains "psp/PSP/SAVEDATA/ULUS...", we want just "ULUS..."
          int skipCount = 0;
          for (int i = 0; i < parts.length; i++) {
            final p = parts[i].toUpperCase();
            if (p == 'PSP' || p == 'SAVEDATA' || p == 'PPSSPP_STATE') {
              skipCount = i + 1;
            }
          }
          if (skipCount > 0) {
             cleanName = p.joinAll(parts.sublist(skipCount));
          }
          if (cleanName.isEmpty) continue;

          final targetPath = p.normalize(entry.name.toLowerCase().endsWith('.ppst') 
              ? p.join(targetStateDir, cleanName)
              : p.join(targetSaveDir, cleanName));

          if (entry.isFile) {
            await backupSave(targetPath);
            final outFile = io.File(targetPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          } else {
            await io.Directory(targetPath).create(recursive: true);
          }
        }
        return true;
      }

      if (filename.toLowerCase().endsWith('.ppst')) {
        final targetPath = p.normalize(p.join(targetStateDir, filename));
        await backupSave(targetPath);
        final outFile = io.File(targetPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(data);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[PPSSPP] Restore error: $e');
      rethrow;
    }
  }
}
