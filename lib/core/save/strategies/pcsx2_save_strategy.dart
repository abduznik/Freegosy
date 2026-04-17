import 'dart:io' as io;
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for PCSX2 (PlayStation 2).
/// Memcards: {systemDir}/memcards/*.ps2
/// States:   {systemDir}/sstates/{stem}.*.
class Pcsx2SaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  Pcsx2SaveStrategy(this._directoryService);

  @override
  String get strategyId => 'pcsx2';

  String _normalizeMemcardFilename(String filename) {
    // Convert "Mcd001 [2026-04-03_20-31-19].ps2" -> "Mcd001.ps2"
    // Convert "Mcd002 [anything].ps2" -> "Mcd002.ps2"
    if (!filename.toLowerCase().endsWith('.ps2')) return filename;
    final match =
        RegExp(r'^(Mcd\d+)', caseSensitive: false).firstMatch(filename);
    if (match != null) {
      return '${match.group(1)}.ps2';
    }
    return filename;
  }

  Future<String> _getSaveRoot() async {
    // 1. Check portable mode first — memcards folder next to exe (Windows)
    final exePath = await _directoryService.findEmulatorExecutable('pcsx2', 'pcsx2-qt.exe');
    if (exePath != null) {
      String exeDir = io.File(exePath).parent.path;
      if (await io.FileSystemEntity.isDirectory(exePath)) {
        exeDir = exePath;
      }
      final portableMemcards = p.join(exeDir, 'memcards');
      if (await io.Directory(portableMemcards).exists()) {
        return exeDir;
      }
    }

    // 2. Linux integration (EmuDeck / RetroDECK)
    if (io.Platform.isLinux) {
      final baseDir = await _directoryService.getEmulatorAppSupportDirectory('pcsx2');
      final bool isSteamDeckEnv = _directoryService.linuxSyncPreset == 'emudeck' || 
                                 _directoryService.linuxSyncPreset == 'retrodeck';

      if (isSteamDeckEnv && (p.basename(baseDir) == 'saves' || p.basename(baseDir) == 'PCSX2')) {
        // EmuDeck mapping returns the folder containing the actual saves/cards
        // RetroDECK mapping returns the PCSX2 folder which also contains memcards/sstates
        return baseDir;
      }
      
      final home = io.Platform.environment['HOME'] ?? '';
      final linuxPath = p.join(home, '.config', 'PCSX2');
      if (await io.Directory(p.join(linuxPath, 'memcards')).exists()) {
        return linuxPath;
      }
    }

    // 3. macOS: ~/Library/Application Support/PCSX2
    if (io.Platform.isMacOS) {
      final home = io.Platform.environment['HOME'] ?? '';
      final macPath = p.join(home, 'Library', 'Application Support', 'PCSX2');
      if (await io.Directory(p.join(macPath, 'memcards')).exists()) {
        return macPath;
      }
    }

    // 4. Fall back to app support directory
    final resolvedPath = await _directoryService.getEmulatorAppSupportDirectory('pcsx2');
    if (!await io.Directory(resolvedPath).exists() && !resolvedPath.contains('Emulation/saves')) {
      throw Exception('Save directory not found for PCSX2 at $resolvedPath. Please launch PCSX2 at least once to generate save data.');
    }
    return resolvedPath;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final root = await _getSaveRoot();
    if (p.basename(root) == 'saves') return root; // EmuDeck direct
    return p.join(root, 'memcards');
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final root = await _getSaveRoot();
    final bool isEmuDeck = p.basename(root) == 'saves';

    final result = <io.File>[];

    // Memory cards
    // EmuDeck: saves/pcsx2/ (mapped as root)
    // RetroDECK: PCSX2/memcards/
    // Native: PCSX2/memcards/
    final memcardsDir = io.Directory(isEmuDeck ? root : p.join(root, 'memcards'));
    if (await memcardsDir.exists()) {
      await for (final entity in memcardsDir.list()) {
        if (entity is! io.File) continue;
        final basename = p.basename(entity.path);
        if (!basename.toLowerCase().endsWith('.ps2')) continue;
        if (basename.contains('[') || basename.contains(']')) continue;
        if (sessionStart != null) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(sessionStart)) continue;
        }
        result.add(entity);
      }
    }

    // Save states
    final stem = getRomStem(game);
    final statesDir = io.Directory(isEmuDeck ? p.join(p.dirname(root), 'states') : p.join(root, 'sstates'));
    if (await statesDir.exists()) {
      await for (final entity in statesDir.list()) {
        if (entity is! io.File) continue;
        if (!p.basename(entity.path).contains(stem)) continue;
        if (sessionStart != null) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(sessionStart)) continue;
        }
        result.add(entity);
      }
    }

    return result;
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      final root = await _getSaveRoot();
      final bool isEmuDeck = p.basename(root) == 'saves';

      // Cloud saves come as zips
      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          final entryLower = entry.name.toLowerCase();
          final targetDir = entryLower.endsWith('.ps2')
              ? (isEmuDeck ? root : p.join(root, 'memcards'))
              : (isEmuDeck ? p.join(p.dirname(root), 'states') : p.join(root, 'sstates'));

          if (entry.isFile) {
            final targetFilename = entryLower.endsWith('.ps2')
                ? _normalizeMemcardFilename(p.basename(entry.name))
                : p.basename(entry.name);
            final targetPath = p.join(targetDir, targetFilename);
            await backupSave(targetPath);
            final outFile = io.File(targetPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          }
        }
        return true;
      }

      // Single file fallback
      final isState = filename.contains('.') &&
          int.tryParse(filename.split('.').last) != null;
      final targetDir = isState 
          ? (isEmuDeck ? p.join(p.dirname(root), 'states') : p.join(root, 'sstates'))
          : (isEmuDeck ? root : p.join(root, 'memcards'));
      
      await io.Directory(targetDir).create(recursive: true);
      final normalizedFilename = filename.toLowerCase().endsWith('.ps2')
          ? _normalizeMemcardFilename(filename)
          : filename;
      final targetPath = p.join(targetDir, normalizedFilename);
      await backupSave(targetPath);
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}
