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
    }

    // 2. Dynamic path resolution (favors EmuDeck if configured)
    final baseDir = await _directoryService.getEmulatorAppSupportDirectory('ppsspp', platformSlug: platformSlug);
    // EmuDeck maps 'ppsspp' -> 'Emulation/saves/ppsspp/PSP' via DirectoryService update
    // If it returns that base, we use it. If it returns .config/ppsspp, we append PSP.
    
    String pspDir = baseDir;
    if (!baseDir.endsWith('PSP')) {
       pspDir = p.join(baseDir, 'PSP');
    }

    if (!await io.Directory(pspDir).exists()) {
      // Create it if we are on EmuDeck to be safe, or fallback
      try {
        await io.Directory(pspDir).create(recursive: true);
      } catch (_) {
        // Fallback to .config if creation fails
        final home = io.Platform.environment['HOME'];
        if (home != null) {
          pspDir = p.join(home, '.config', 'ppsspp', 'PSP');
        }
      }
    }
    return pspDir;
  }


  /// Reads PARAM.SFO file and extracts the game title.
  /// Returns the title string if found, or null if parsing fails.
  Future<String?> _readParamSfoTitle(String folderPath) async {
    try {
      final sfoFile = io.File(p.join(folderPath, 'PARAM.SFO'));
      if (!await sfoFile.exists()) return null;

      final bytes = await sfoFile.readAsBytes();
      if (bytes.length < 20) return null;

      final byteData = ByteData.view(bytes.buffer);

      // Magic: 0x00PSF
      if (bytes[0] != 0x00 || bytes[1] != 0x50 ||
          bytes[2] != 0x53 || bytes[3] != 0x46) {
        return null;
      }

      final keyTableOffset  = byteData.getUint32(8,  Endian.little);
      final dataTableOffset = byteData.getUint32(12, Endian.little);
      final entriesCount    = byteData.getUint32(16, Endian.little);

      for (int i = 0; i < entriesCount; i++) {
        final entryBase = 20 + i * 16;
        if (entryBase + 16 > bytes.length) break;

        final keyRelOffset  = byteData.getUint16(entryBase + 0,  Endian.little);
        final dataLen       = byteData.getUint32(entryBase + 4,  Endian.little);
        final dataRelOffset = byteData.getUint32(entryBase + 12, Endian.little);

        // Read null-terminated key string
        final keyStart = keyTableOffset + keyRelOffset;
        final keyBytes = <int>[];
        int j = keyStart;
        while (j < bytes.length && bytes[j] != 0) {
          keyBytes.add(bytes[j++]);
        }
        final key = utf8.decode(keyBytes);

        if (key == 'TITLE') {
          final valueStart = dataTableOffset + dataRelOffset;
          final valueEnd   = valueStart + dataLen;
          if (valueEnd > bytes.length) return null;

          final titleBytes = bytes.sublist(valueStart, valueEnd);
          final nullIdx = titleBytes.indexOf(0);
          final actual  = nullIdx != -1 ? titleBytes.sublist(0, nullIdx) : titleBytes;
          return utf8.decode(actual);
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error reading PARAM.SFO: $e');
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

    // --- Handle SAVEDATA folders ---
    final saveDataDir = io.Directory(p.join(pspDir, 'SAVEDATA'));
    if (await saveDataDir.exists()) {
      final allSubdirs = await saveDataDir.list().where((e) => e is io.Directory).cast<io.Directory>().toList();

      if (allSubdirs.isNotEmpty) {
        final foldersWithTitles = <Map<String, dynamic>>[];
        for (final dir in allSubdirs) {
          final title = await _readParamSfoTitle(dir.path);
          if (title != null) {
            foldersWithTitles.add({
              'dir': dir,
              'title': title,
              'modified': (await dir.stat()).modified,
            });
          }
        }

        final gameWords = game.name
            .toLowerCase()
            .replaceAll(RegExp(r"[^a-z0-9\s]"), '')
            .split(' ')
            .where((w) => w.length >= 2)
            .toList();

        final matchingFolders = foldersWithTitles.where((entry) {
          final folderTitleLower = (entry['title'] as String).toLowerCase();
          return gameWords.any((word) => folderTitleLower.contains(word));
        }).toList();

        List<io.Directory> foldersToZip = [];

        if (matchingFolders.length == 1) {
          foldersToZip.add(matchingFolders.first['dir'] as io.Directory);
        } else if (matchingFolders.length > 1) {
          foldersToZip.addAll(matchingFolders.map((e) => e['dir'] as io.Directory));
        } else {
          // Zero matches: fall back to recency
          if (foldersWithTitles.isNotEmpty) {
            foldersWithTitles.sort((a, b) => (b['modified'] as DateTime).compareTo(a['modified'] as DateTime));
            foldersToZip.add(foldersWithTitles.first['dir'] as io.Directory);
            debugPrint('No exact PARAM.SFO title match for "${game.name}". Falling back to most recently modified folder: ${(foldersWithTitles.first['dir'] as io.Directory).path}');
          }
        }

        if (foldersToZip.isNotEmpty) {
          debugPrint('[PPSSPP] Zipping folders: ${foldersToZip.map((d) => d.path).toList()}');
          final zipPath = p.join(pspDir, '${game.id}.saves.zip');
          final encoder = ZipFileEncoder();
          encoder.create(zipPath);
          for (final dir in foldersToZip) {
            // Important: we include the folder name (e.g. ULUS10001) so restore can recreate it
            await encoder.addDirectory(dir);
          }
          encoder.close();
          result.add(io.File(zipPath));
        }
      }
    }

    // --- Handle PPSSPP_STATE (.ppst files) ---
    final statesDir = io.Directory(p.join(pspDir, 'PPSSPP_STATE'));
    if (await statesDir.exists()) {
      final stem = getRomStem(game);
      final stateFile = io.File(p.join(pspDir, 'PPSSPP_STATE', '$stem.ppst'));
      if (await stateFile.exists()) {
        if (sessionStart == null ||
            (await stateFile.stat()).modified.isAfter(sessionStart)) {
          result.add(stateFile);
        }
      }
    }

    return result;
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final pspDir = await _getPspDir(platformSlug: game.platformSlug);

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        
        // If pspDir already ends with SAVEDATA (from symlink), use it directly.
        // Otherwise, append SAVEDATA.
        String targetBaseDir = pspDir;
        if (!pspDir.toUpperCase().endsWith('SAVEDATA')) {
          targetBaseDir = p.join(pspDir, 'SAVEDATA');
        }
        
        // Ensure the leaf dir exists
        await io.Directory(targetBaseDir).create(recursive: true);

        for (final entry in archive) {
          if (entry.name.contains('.bak')) continue;
          final targetPath = p.join(targetBaseDir, entry.name);
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
        final targetPath = p.join(pspDir, 'PPSSPP_STATE', filename);
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
