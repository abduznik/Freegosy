import 'dart:io' as io;
import 'dart:math' as math;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../disc/serial_extraction_service.dart';
import '../../platform/platform_info.dart';
import '../../romm/romm_models.dart';
import '../../storage/app_preferences.dart';
import '../../storage/directory_service.dart';
import '../save_state_info.dart';
import '../save_strategy.dart';
import '../state_sync_capable.dart';
import 'pcsx2_state_file.dart';

/// Save strategy for PCSX2 (PlayStation 2).
/// Memcards: {systemDir}/memcards/*.ps2
/// States:   {systemDir}/sstates/{SERIAL (CRC).NN.p2s} — synced separately
///           through [StateSyncCapable] / StateSyncService, not by this
///           strategy's save methods.
class Pcsx2SaveStrategy extends SaveStrategy with StateSyncCapable {
  final DirectoryService _directoryService;
  final PlatformInfo _platform;
  final SerialExtractionService _serialExtractionService;

  /// PS2's `SYSTEM.CNF` boot line, e.g. `BOOT2 = cdrom0:\SLUS_123.45;1` —
  /// the "2" distinguishes it from PS1's `BOOT =` line so a PS1 BIOS won't
  /// try to boot a PS2 disc.
  static final _bootLinePattern = RegExp(
      r'BOOT2\s*=\s*cdrom[^:]*:\\?([A-Z]{4}[_-]\d{3}[.]\d{2})',
      caseSensitive: false);

  Pcsx2SaveStrategy(this._directoryService, AppPreferences prefs,
      {PlatformInfo? platform, SerialExtractionService? serialExtractionService})
      : _platform = platform ?? PlatformInfo.current,
        _serialExtractionService = serialExtractionService ??
            SerialExtractionService(_directoryService, prefs, platform: platform);

  @override
  String get strategyId => 'pcsx2';

  /// Extracts the PS2 game serial (e.g. "SLUS-12345") from the ROM. See
  /// [SerialExtractionService] for the filename/CHD/ISO extraction strategy.
  /// Returns null if the serial cannot be determined.
  Future<String?> _extractSerial(String romPath) => _serialExtractionService.extractSerial(
        romPath: romPath,
        bootLinePattern: _bootLinePattern,
        chdmanCandidates: [(emulatorId: 'pcsx2', exeName: _getEmuExe())],
      );

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
    if (_platform.isWindows) return 'pcsx2-qt.exe';
    if (_platform.isMacOS) return 'PCSX2.app/Contents/MacOS/PCSX2';
    return 'pcsx2-qt';
  }

  /// PCSX2's own state naming: `SERIAL (CRC).NN.p2s` or
  /// `SERIAL (CRC).resume.p2s` (VMManager::GetSaveStateFileName). The
  /// character class excludes path separators; `.p2s.backup` doesn't match.
  static final _stateFilePattern = RegExp(
      r'^([A-Za-z0-9_-]+) \([0-9A-Fa-f]{8}\)\.(?:\d{2}|resume)\.p2s$');

  static String _serialKey(String serial) =>
      serial.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  @override
  Future<String> stateDirectory(Game game, String romPath) async {
    final root = await _getSaveRoot();
    final isEmuDeck = p.basename(root) == 'saves';
    return isEmuDeck
        ? p.join(p.dirname(root), 'states')
        : p.join(root, 'sstates');
  }

  @override
  Future<bool Function(String fileName)?> stateFileMatcher(
      Game game, String romPath) async {
    final serial = await _extractSerial(romPath);
    if (serial == null) return null;
    final wanted = _serialKey(serial);
    return (String fileName) {
      final match = _stateFilePattern.firstMatch(fileName);
      return match != null && _serialKey(match.group(1)!) == wanted;
    };
  }

  /// `.p2s` files are zip archives: they start with a local file header
  /// (`PK\x03\x04`) and end with an end-of-central-directory record
  /// (`PK\x05\x06`, 22 bytes plus a comment of up to 64 KiB). Checking both
  /// ends also rejects a write that was cut off partway.
  @override
  bool looksLikeValidState(Uint8List bytes) {
    if (bytes.length < 26 ||
        bytes[0] != 0x50 || bytes[1] != 0x4B || bytes[2] != 0x03 || bytes[3] != 0x04) {
      return false;
    }
    final earliest = math.max(4, bytes.length - 22 - 0xFFFF);
    for (var i = bytes.length - 22; i >= earliest; i--) {
      if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06) {
        return true;
      }
    }
    return false;
  }

  static final _slotPattern = RegExp(r'\.(\d{2}|resume)\.p2s$');

  @override
  StateSlot slotOf(String fileName) {
    final match = _slotPattern.firstMatch(fileName);
    if (match == null || !_stateFilePattern.hasMatch(fileName)) {
      return UnknownStateSlot(fileName);
    }
    final slot = match.group(1)!;
    return slot == 'resume' ? const AutoStateSlot() : NumberedStateSlot(int.parse(slot));
  }

  @override
  Future<StateFileInfo> describeState(io.File file) async {
    final base = await super.describeState(file);
    final header = await Pcsx2StateFile.readVersion(file);
    return StateFileInfo(
      savedAt: base.savedAt,
      emulatorVersion: header?.version,
      formatId: header?.formatId,
    );
  }

  @override
  Future<Uint8List?> stateScreenshot(io.File file) => Pcsx2StateFile.readScreenshot(file);

  Future<String> _getSaveRoot() async {
    // 1. Check portable mode first — memcards folder next to exe (Windows)
    final exePath = await _directoryService.findEmulatorExecutable('pcsx2', _getEmuExe());
    if (exePath != null) {
      String exeDir = io.File(exePath).parent.path;
      if (_platform.isMacOS && exePath.contains('.app/Contents/MacOS/')) {
        exeDir = io.File(exePath).parent.parent.parent.parent.path;
      } else if (await io.FileSystemEntity.isDirectory(exePath)) {
        exeDir = exePath;
      }
      final portableMemcards = p.join(exeDir, 'memcards');
      debugPrint('[PCSX2] exe=$exePath → checking portable memcards at: $portableMemcards');
      if (await io.Directory(portableMemcards).exists()) {
        debugPrint('[PCSX2] portable save root found: $exeDir');
        return exeDir;
      }
      debugPrint('[PCSX2] portable memcards missing at: $portableMemcards');
    } else {
      debugPrint('[PCSX2] no pcsx2 executable found via DirectoryService');
    }

    // 2. Linux integration (EmuDeck / RetroDECK)
    if (_platform.isLinux) {
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
      
      final home = _platform.environment['HOME'] ?? '';
      final linuxPath = p.join(home, '.config', 'PCSX2');
      if (await io.Directory(p.join(linuxPath, 'memcards')).exists()) {
        return linuxPath;
      }
    }

    // 3. macOS: ~/Library/Application Support/PCSX2
    if (_platform.isMacOS) {
      final home = _platform.environment['HOME'] ?? '';
      final macPath = p.join(home, 'Library', 'Application Support', 'PCSX2');
      if (await io.Directory(p.join(macPath, 'memcards')).exists()) {
        return macPath;
      }
    }

    // 4. Fall back to app support directory
    final resolvedPath = await _directoryService.getEmulatorAppSupportDirectory('pcsx2');
    debugPrint('[PCSX2] app support save root candidate: $resolvedPath');
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
    debugPrint('[PCSX2] getSaveFiles root=$root  isEmuDeck=$isEmuDeck  syncMode=$syncMode  sessionStart=$sessionStart');

    final result = <io.File>[];

    if (syncMode == 'saves' || syncMode == 'both') {
      // --- Layer 1: per-game folder saves (saves/{Serial}/) ---
      // NOTE: PCSX2 itself does NOT create this layout — verified against
      // upstream source. Its memcards live in the memcards/ folder as
      // Mcd001.ps2/Mcd002.ps2 (file OR folder type). This `saves/{Serial}`
      // check is kept as a best-effort for user-created structures and some
      // third-party setups; it only fires if the folder actually exists.
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
          debugPrint('[PCSX2]   per-game folder save found: ${foundDir.path}');
          final hasChanges = sessionStart == null ||
              foundDir
                  .listSync(recursive: true)
                  .whereType<io.File>()
                  .any((f) => f.statSync().modified.isAfter(
                      sessionStart.subtract(const Duration(seconds: 2))));
          if (hasChanges) {
            result.add(io.File(foundDir.path));
          } else {
            debugPrint('[PCSX2]   per-game folder has no changes since sessionStart — skipping');
          }
        } else {
          debugPrint('[PCSX2]   no per-game folder for $serial (checked ${perGameDir.path} and ${perGameDirAlt.path})');
        }
      } else {
        debugPrint('[PCSX2]   serial null — skipping per-game folder layer');
      }

      // --- Layer 2: memcards (Mcd001.ps2 / Mcd002.ps2) ---
      // Real PCSX2 memcards live in the memcards/ folder. They can be either
      // a FILE (8MB image) or a DIRECTORY (PCSX2 "folder memcard" — detected
      // upstream via DirectoryExists on the .ps2 path). Both carry the same
      // McdXXX.ps2 name. Only fall back to this if no per-game folder matched.
      if (result.isEmpty) {
        final memcardsDir =
            io.Directory(isEmuDeck ? root : p.join(root, 'memcards'));
        if (await memcardsDir.exists()) {
          debugPrint('[PCSX2]   scanning memcards at: ${memcardsDir.path}');
          await for (final entity in memcardsDir.list()) {
            // Accept both files and folder-type (directory) memcards.
            if (entity is! io.File && entity is! io.Directory) continue;
            final basename = p.basename(entity.path);
            if (!basename.toLowerCase().endsWith('.ps2')) continue;
            // Skip timestamped backup copies (e.g. "Mcd001 [2026-04-03_20-31-19].ps2")
            if (basename.contains('[') || basename.contains(']')) continue;

            // A folder-type memcard can contain per-game folders — PCSX2
            // itself creates one folder per save artifact (data, system
            // config, etc.), all sharing this game's <region-prefix><serial>
            // as a name prefix (e.g. "BASLUS-20152AC04" + "BASLUS-20152SYS").
            // Bundle only the folders matching THIS game, not the whole
            // shared card: restoreSave recognises a bare artifact folder at
            // the zip root (no card wrapper needed) and places it back into
            // whichever local folder-type memcard slot exists, so uploading
            // the whole card here would just re-upload every other game
            // sharing it on every push.
            if (entity is io.Directory && serial != null) {
              final childDirectories =
                  entity.listSync().whereType<io.Directory>().toList();
              if (childDirectories.isNotEmpty) {
                final matchingDirectories = childDirectories.where((directory) =>
                    _serialMatchesDirectory(p.basename(directory.path), serial)).toList();
                if (matchingDirectories.isEmpty) {
                  debugPrint('[PCSX2]   no serial folder for $serial in ${entity.path} — skipping folder card');
                  continue;
                }
                for (final directory in matchingDirectories) {
                  // The card directory's own mtime only changes when its
                  // immediate children list changes (an artifact folder
                  // added/removed) — not when PCSX2 rewrites a file deep
                  // inside an existing artifact folder. Check each matching
                  // folder's contents recursively instead, the same way
                  // Layer 1 already does for saves/{Serial}/.
                  final hasChanges = sessionStart == null ||
                      directory
                          .listSync(recursive: true)
                          .whereType<io.File>()
                          .any((f) => f.statSync().modified.isAfter(
                              sessionStart.subtract(const Duration(seconds: 2))));
                  if (!hasChanges) {
                    debugPrint('[PCSX2]   ${directory.path} has no changes since sessionStart — skipping');
                    continue;
                  }
                  debugPrint('[PCSX2]   serial folder selected: ${directory.path}');
                  result.add(io.File(directory.path));
                }
                continue;
              }
            }
            if (sessionStart != null) {
              final stat = await entity.stat();
              if (stat.modified
                  .isBefore(sessionStart.subtract(const Duration(seconds: 2)))) {
                continue;
              }
            }
            debugPrint('[PCSX2]   memcard added: ${entity.path} '
                '(${entity is io.Directory ? "folder card" : "file card"})');
            result.add(io.File(entity.path));
          }
        } else {
          debugPrint('[PCSX2]   memcards dir missing: ${memcardsDir.path}');
        }
      }
    }

    debugPrint('[PCSX2]   → ${result.length} save file(s) returned');
    return result;
  }

  /// The 2-letter prefix PCSX2 prepends to a game's serial when naming its
  /// folder-memcard save-artifact directories (e.g. "BASLUS-20152AC04" for
  /// a US game whose serial is "SLUS-20152"). Keyed off the serial's region
  /// letter, same scheme as RomM's Argosy launcher uses for the same data:
  /// U (US) -> BA, E (Europe) -> BE, P/J/K (Japan/Asia) -> BI.
  String _ps2RegionPrefix(String serial) {
    if (serial.length < 3) return 'BA';
    switch (serial[2].toUpperCase()) {
      case 'E':
        return 'BE';
      case 'P':
      case 'J':
      case 'K':
        return 'BI';
      default:
        return 'BA';
    }
  }

  /// Matches a folder-memcard directory against a game's serial. Real
  /// PCSX2 folders are named `<region-prefix><dash-serial><suffix>` (the
  /// suffix distinguishes sibling artifacts like data vs. system config —
  /// e.g. "AC04"/"SYS"), so this checks a prefix match against that shape
  /// rather than requiring an exact match against the bare serial.
  bool _serialMatchesDirectory(String directoryName, String serial) {
    String normalize(String value) => value.toUpperCase().replaceAll('_', '-');
    final normalizedDir = normalize(directoryName);
    final normalizedSerial = normalize(serial);
    if (normalizedDir == normalizedSerial) return true;
    return normalizedDir.startsWith('${_ps2RegionPrefix(normalizedSerial)}$normalizedSerial');
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
        // Folder-type memcard bundle: "Mcd001.ps2/<serial>/<file>". This is
        // how the push side packs folder-type memcards (see
        // encoder.addDirectory(...) on the push path) — the McdNNN.ps2
        // directory itself contains the per-game serial folders.
        final memcardFolderPattern =
            RegExp(r'^(Mcd\d+\.ps2)[/\\]', caseSensitive: false);

        // A folder-type memcard bundle pushed by another RomM client (e.g.
        // Argosy, the Android launcher) may not use the McdNNN.ps2 naming
        // at all — Argosy identifies a card by the presence of a
        // `_pcsx2_superblock` file at its root rather than by name, so its
        // card folder can be called anything. Detect that shape by finding
        // whichever top-level folder (if any) contains a superblock entry.
        String? cardFolderWithSuperblock;
        for (final entry in archive) {
          if (!entry.isFile) continue;
          if (p.basename(entry.name) != '_pcsx2_superblock') continue;
          final topLevel = RegExp(r'^([^/\\]+)[/\\]').firstMatch(entry.name)?.group(1);
          if (topLevel != null) {
            cardFolderWithSuperblock = topLevel;
            break;
          }
        }
        final superblockCardPattern = cardFolderWithSuperblock != null
            ? RegExp('^${RegExp.escape(cardFolderWithSuperblock)}[/\\\\]')
            : null;

        // A bare per-game artifact folder with no card wrapper at all — the
        // narrowed push shape: getSaveFiles only bundles the folders that
        // match the current game's serial (not the whole shared card), so
        // a push zip's top level can be e.g. "BASLUS-20152AC04/icon.sys"
        // directly. Same <region-prefix><dash-serial><suffix> shape PCSX2
        // itself uses (see _serialMatchesDirectory). The suffix has no
        // fixed shape — real cards show both glued (e.g. "AC04") and
        // dash-separated (e.g. "-PROFILE") suffixes, and plenty of folders
        // have no suffix at all — so it's just "anything but a separator".
        final ps2FolderArtifactPattern = RegExp(
          r'^(B[AEI]S[A-Z]{3,4}-\d{5}[^/\\]*)[/\\]',
          caseSensitive: false,
        );

        // Both shapes above need to land inside whichever local
        // folder-type memcard slot already exists — the zip's own card
        // name (if any) can't be used directly, since PCSX2 only
        // recognizes memcard slots by the local McdNNN.ps2 naming
        // convention, not by whatever name the originating client used.
        String? localFolderMemcardSlot;
        if (cardFolderWithSuperblock != null ||
            archive.any((e) => e.isFile && ps2FolderArtifactPattern.hasMatch(e.name))) {
          final memcardsDirForLookup =
              io.Directory(isEmuDeck ? root : p.join(root, 'memcards'));
          if (await memcardsDirForLookup.exists()) {
            await for (final entity in memcardsDirForLookup.list()) {
              if (entity is io.Directory &&
                  p.basename(entity.path).toLowerCase().endsWith('.ps2')) {
                localFolderMemcardSlot = p.basename(entity.path);
                break;
              }
            }
          }
          localFolderMemcardSlot ??= 'Mcd001.ps2';
        }

        for (final entry in archive) {
          if (!entry.isFile) continue;
          if (entry.name == 'freegosy_sync.txt') continue;

          final entryLower = entry.name.toLowerCase();
          final serialMatch = serialPattern.firstMatch(entry.name);
          final memcardFolderMatch = memcardFolderPattern.firstMatch(entry.name);
          final superblockCardMatch = superblockCardPattern?.firstMatch(entry.name);
          final ps2ArtifactMatch = ps2FolderArtifactPattern.firstMatch(entry.name);

          String targetPath;
          // PCSX2 itself (and other RomM clients like Argosy) actively
          // scans/manages a folder-type memcard's contents — a stray
          // ".bak"/".bak1"/".bak2" sibling left inside it by backupSave()
          // has been observed to make PCSX2 refuse to save again until the
          // extra files are manually removed. Skip the per-file backup for
          // anything landing inside one of those managed folders; other
          // restore targets (saves/{Serial}/, flat memcard files, save
          // states) aren't scanned by anything external, so keep it there.
          final targetIsInsideManagedMemcardFolder =
              memcardFolderMatch != null || superblockCardMatch != null || ps2ArtifactMatch != null;
          if (serialMatch != null) {
            // Per-game folder save — restore to saves/{Serial}/
            final serial = serialMatch.group(1)!.toUpperCase();
            final savesDir = isEmuDeck ? root : p.join(root, 'saves');
            final relativePath = entry.name.substring(serialMatch.group(0)!.length);
            targetPath = p.normalize(p.join(savesDir, serial, relativePath));
          } else if (memcardFolderMatch != null) {
            // Folder-type memcard bundle — restore to memcards/{McdNNN.ps2}/
            final memcardFolderName = memcardFolderMatch.group(1)!;
            final memcardsDir = isEmuDeck ? root : p.join(root, 'memcards');
            final relativePath =
                entry.name.substring(memcardFolderMatch.group(0)!.length);
            targetPath = p.normalize(
                p.join(memcardsDir, memcardFolderName, relativePath));
          } else if (superblockCardMatch != null) {
            // Folder-type memcard bundle from a non-Mcd-named card (see
            // detection above) — restore into the resolved local slot.
            final memcardsDir = isEmuDeck ? root : p.join(root, 'memcards');
            final relativePath =
                entry.name.substring(superblockCardMatch.group(0)!.length);
            targetPath = p.normalize(
                p.join(memcardsDir, localFolderMemcardSlot!, relativePath));
          } else if (ps2ArtifactMatch != null) {
            // Bare per-game artifact folder, no card wrapper at all (the
            // narrowed push shape) — restore into the resolved local slot,
            // preserving the artifact folder name itself (e.g.
            // "BASLUS-20152AC04") since that's what identifies it to PCSX2.
            final artifactFolderName = ps2ArtifactMatch.group(1)!;
            final memcardsDir = isEmuDeck ? root : p.join(root, 'memcards');
            final relativePath =
                entry.name.substring(ps2ArtifactMatch.group(0)!.length);
            targetPath = p.normalize(
                p.join(memcardsDir, localFolderMemcardSlot!, artifactFolderName, relativePath));
          } else if (entryLower.endsWith('.ps2')) {
            // Shared memcard — restore to memcards/ with normalized name
            final memcardsDir = isEmuDeck ? root : p.join(root, 'memcards');
            final targetFilename = _normalizeMemcardFilename(p.basename(entry.name));
            targetPath = p.normalize(p.join(memcardsDir, targetFilename));
          } else {
            // Not a memory-card shape. Older Freegosy versions bundled PCSX2
            // save states (`*.p2s`) into the game-save zip; states now sync
            // separately through StateSyncService, so never write them here.
            debugPrint('[PCSX2]   skipping non-memcard entry: ${entry.name}');
            continue;
          }

          if (!targetIsInsideManagedMemcardFolder) await backupSave(targetPath);
          final outFile = io.File(targetPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
        }
        return true;
      }

      // Single file fallback
      if (_stateFilePattern.hasMatch(p.basename(filename))) {
        debugPrint('[PCSX2]   ignoring legacy save-state upload: $filename');
        return true;
      }
      final targetDir = isEmuDeck ? root : p.join(root, 'memcards');
      
      final normalizedFilename = filename.toLowerCase().endsWith('.ps2')
          ? _normalizeMemcardFilename(filename)
          : filename;
      final targetPath = p.normalize(p.join(targetDir, normalizedFilename));
      await io.Directory(p.dirname(targetPath)).create(recursive: true);
      await backupSave(targetPath);
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      debugPrint('[PCSX2] restoreSave failed: $e');
      return false;
    }
  }
}
