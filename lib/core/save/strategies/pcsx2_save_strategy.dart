import 'dart:convert';
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

  /// Extracts the PS2 game serial (e.g. "SLUS-12345") from the ROM.
  ///
  /// Strategy:
  /// 1. Try to parse it from the ROM filename — many No-Intro/Redump sets
  ///    include the serial like "Ico (SCUS-97113)".
  /// 2. Read `SYSTEM.CNF` from inside the ISO. The file contains a line like
  ///    `BOOT2 = cdrom0:\SLUS_123.45;1` — the serial is the filename without
  ///    the path, with `_` replaced by `-` and `.` removed before the digit part.
  ///
  /// Returns null if the serial cannot be determined.
  Future<String?> _extractSerial(String romPath) async {
    // 1. Try filename first — fast, no file I/O needed for most sets
    final base = p.basenameWithoutExtension(romPath);
    final filenameMatch =
        RegExp(r'\b(S[A-Z]{3,4}[-_]\d{3}[\._]?\d{2})\b', caseSensitive: false)
            .firstMatch(base);
    if (filenameMatch != null) {
      return _normalizeSerial(filenameMatch.group(1)!);
    }

    // 2. Read SYSTEM.CNF from inside the ISO
    final ext = p.extension(romPath).toLowerCase();
    if (ext == '.iso' || ext == '.bin') {
      try {
        final file = await io.File(romPath).open(mode: io.FileMode.read);
        // ISO 9660: Primary Volume Descriptor at sector 16 (2048 bytes/sector).
        // Directory entries start at the location given in the PVD.
        // We do a targeted text scan for "SYSTEM.CNF" boot line instead of
        // implementing full ISO 9660 parsing — fast and sufficient.
        const chunkSize = 65536; // 64 KB — SYSTEM.CNF is always near the start
        final bytes = Uint8List(chunkSize);
        await file.readInto(bytes);
        await file.close();
        final text = latin1.decode(bytes, allowInvalid: true);
        final cnfMatch = RegExp(
                r'BOOT2\s*=\s*cdrom[^:]*:\\?([A-Z]{4}_\d{3}\.\d{2})',
                caseSensitive: false)
            .firstMatch(text);
        if (cnfMatch != null) {
          return _normalizeSerial(cnfMatch.group(1)!);
        }
      } catch (_) {}
    }

    return null;
  }

  /// Normalises a raw serial string to PCSX2's folder naming convention.
  /// "SLUS_123.45" → "SLUS-12345", "SLUS-123.45" → "SLUS-12345"
  String _normalizeSerial(String raw) {
    // Replace underscore separator with dash, remove the dot before digits
    var s = raw.toUpperCase().replaceAll('_', '-');
    // "SLUS-123.45" → "SLUS-12345"
    s = s.replaceAllMapped(RegExp(r'(\d{3})\.(\d{2})'), (m) => '${m[1]}${m[2]}');
    return s;
  }

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

  String _getEmuExe() {
    if (io.Platform.isWindows) return 'pcsx2-qt.exe';
    if (io.Platform.isMacOS) return 'PCSX2.app/Contents/MacOS/PCSX2';
    return 'pcsx2-qt';
  }

  Future<String> _getSaveRoot() async {
    // 1. Check portable mode first — memcards folder next to exe (Windows)
    final exePath = await _directoryService.findEmulatorExecutable('pcsx2', _getEmuExe());
    if (exePath != null) {
      String exeDir = io.File(exePath).parent.path;
      if (io.Platform.isMacOS && exePath.contains('.app/Contents/MacOS/')) {
        exeDir = io.File(exePath).parent.parent.parent.parent.path;
      } else if (await io.FileSystemEntity.isDirectory(exePath)) {
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
      final bool isEmuDeck = _directoryService.linuxSyncPreset == 'emudeck' || 
                             baseDir.contains('Emulation/saves');
      
      if (isEmuDeck) {
        // EmuDeck: saves are in Emulation/saves/pcsx2/saves
        if (p.basename(baseDir) == 'saves') return baseDir;
        final candidate = p.join(baseDir, 'saves');
        if (await io.Directory(candidate).exists()) return candidate;
        return baseDir;
      }
      
      if (_directoryService.linuxSyncPreset == 'retrodeck') {
        // RetroDECK: PCSX2/memcards/
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

    if (syncMode == 'saves' || syncMode == 'both') {
      // --- Layer 1: PCSX2 Qt per-game folder saves (saves/{Serial}/) ---
      // PCSX2 1.7+ stores saves in a per-game folder named after the serial.
      // This takes priority over shared memcard files when present.
      final serial = await _extractSerial(romPath);
      if (serial != null) {
        final perGameDir = io.Directory(isEmuDeck
            ? p.join(root, serial)
            : p.join(root, 'saves', serial));
        // Also check without the saves/ sub-level (some portable installs)
        final perGameDirAlt =
            io.Directory(p.join(root, serial));

        io.Directory? foundDir;
        if (await perGameDir.exists()) {
          foundDir = perGameDir;
        } else if (await perGameDirAlt.exists()) {
          foundDir = perGameDirAlt;
        }

        if (foundDir != null) {
          final hasChanges = sessionStart == null ||
              foundDir
                  .listSync(recursive: true)
                  .whereType<io.File>()
                  .any((f) => f.statSync().modified.isAfter(
                      sessionStart.subtract(const Duration(seconds: 2))));
          if (hasChanges) {
            result.add(io.File(foundDir.path));
          }
        }
      }

      // --- Layer 2: Shared memcard files (Mcd001.ps2 / Mcd002.ps2) ---
      // Used by PCSX2 1.6 and earlier, and still common in portable setups.
      // Only fall back to this if no per-game folder was found.
      if (result.isEmpty) {
        final memcardsDir =
            io.Directory(isEmuDeck ? root : p.join(root, 'memcards'));
        if (await memcardsDir.exists()) {
          await for (final entity in memcardsDir.list()) {
            if (entity is! io.File) continue;
            final basename = p.basename(entity.path);
            if (!basename.toLowerCase().endsWith('.ps2')) continue;
            // Skip timestamped backup copies (e.g. "Mcd001 [2026-04-03_20-31-19].ps2")
            if (basename.contains('[') || basename.contains(']')) continue;
            if (sessionStart != null) {
              final stat = await entity.stat();
              if (stat.modified
                  .isBefore(sessionStart.subtract(const Duration(seconds: 2)))) {
                continue;
              }
            }
            result.add(entity);
          }
        }
      }
    }

    // --- Save states (stem-matched, both layers) ---
    if (syncMode == 'states' || syncMode == 'both') {
      final stem = getRomStem(game);
      final statesDir = io.Directory(
          isEmuDeck ? p.join(p.dirname(root), 'states') : p.join(root, 'sstates'));
      if (await statesDir.exists()) {
        await for (final entity in statesDir.list()) {
          if (entity is! io.File) continue;
          if (!p.basename(entity.path).contains(stem)) continue;
          if (sessionStart != null) {
            final stat = await entity.stat();
            if (stat.modified
                .isBefore(sessionStart.subtract(const Duration(seconds: 2)))) {
              continue;
            }
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
      final root = await _getSaveRoot();
      final bool isEmuDeck = p.basename(root) == 'saves';

      // Cloud saves come as zips
      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        // Detect whether this is a per-game folder bundle:
        // entries will have a leading path component matching a PS2 serial
        // (e.g. "SLUS-12345/filename.p2s").
        final serialPattern = RegExp(r'^(S[A-Z]{3,4}-\d{5})[/\\]', caseSensitive: false);
        for (final entry in archive) {
          if (!entry.isFile) continue;
          if (entry.name == 'freegosy_sync.txt') continue;

          final entryLower = entry.name.toLowerCase();
          final serialMatch = serialPattern.firstMatch(entry.name);

          String targetPath;
          if (serialMatch != null) {
            // Per-game folder save — restore to saves/{Serial}/
            final serial = serialMatch.group(1)!.toUpperCase();
            final savesDir = isEmuDeck ? root : p.join(root, 'saves');
            final relativePath = entry.name.substring(serialMatch.group(0)!.length);
            targetPath = p.normalize(p.join(savesDir, serial, relativePath));
          } else if (entryLower.endsWith('.ps2')) {
            // Shared memcard — restore to memcards/ with normalized name
            final memcardsDir = isEmuDeck ? root : p.join(root, 'memcards');
            final targetFilename = _normalizeMemcardFilename(p.basename(entry.name));
            targetPath = p.normalize(p.join(memcardsDir, targetFilename));
          } else {
            // Save state
            final statesDir = isEmuDeck
                ? p.join(p.dirname(root), 'states')
                : p.join(root, 'sstates');
            targetPath = p.normalize(p.join(statesDir, p.basename(entry.name)));
          }

          await backupSave(targetPath);
          final outFile = io.File(targetPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
        }
        return true;
      }

      // Single file fallback
      final isState = filename.contains('.') &&
          int.tryParse(filename.split('.').last) != null;
      final targetDir = isState 
          ? (isEmuDeck ? p.join(p.dirname(root), 'states') : p.join(root, 'sstates'))
          : (isEmuDeck ? root : p.join(root, 'memcards'));
      
      final normalizedFilename = filename.toLowerCase().endsWith('.ps2')
          ? _normalizeMemcardFilename(filename)
          : filename;
      final targetPath = p.normalize(p.join(targetDir, normalizedFilename));
      await io.Directory(p.dirname(targetPath)).create(recursive: true);
      await backupSave(targetPath);
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}
