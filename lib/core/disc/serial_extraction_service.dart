import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../platform/platform_info.dart';
import '../storage/app_preferences.dart';
import '../storage/directory_service.dart';

/// An emulator install to check beside for a `chdman` executable, in
/// addition to the app itself and (always) MAME.
typedef ChdmanCandidate = ({String emulatorId, String exeName});

/// Extracts a disc serial (e.g. "SLUS-12345") from a ROM path.
///
/// Shared across per-console save strategies whose games are identified by
/// a Sony-style disc serial (PS1, PS2, ...): the serial shape, filename
/// convention, and `chdman`-based CHD handling are identical between them.
/// What differs is the boot-line format inside `SYSTEM.CNF` (PS1 uses
/// `BOOT =`, PS2 uses `BOOT2 =`) and which emulator to check beside for
/// `chdman` — both are caller-supplied parameters.
class SerialExtractionService {
  final DirectoryService _directoryService;
  final AppPreferences _prefs;
  final PlatformInfo _platform;

  SerialExtractionService(this._directoryService, this._prefs, {PlatformInfo? platform})
      : _platform = platform ?? PlatformInfo.current;

  /// Bytes read from the start of the disc when probing for the boot line.
  /// The ISO9660 primary volume descriptor lives at sector 16 (byte 0x8000)
  /// and these consoles place their boot files in the root directory, so
  /// this is almost always enough without extracting the whole (often
  /// multi-GB) image.
  static const _headerScanBytes = 4 * 1024 * 1024;

  /// Extracts the disc serial from [romPath].
  ///
  /// Strategy:
  /// 1. Try to parse it from the ROM filename — many No-Intro/Redump sets
  ///    include the serial like "Ico (SCUS-97113)".
  /// 2. Read the boot line from inside the disc image (CHD, ISO, or BIN),
  ///    matching [bootLinePattern] against a bounded chunk of its header.
  ///    [bootLinePattern] must capture the raw serial in its first group.
  ///
  /// [chdmanCandidates] lists additional emulator installs to check beside
  /// for `chdman` (MAME is always checked, since it ships `chdman`
  /// alongside its own executable on most platforms).
  ///
  /// Returns null if the serial cannot be determined.
  Future<String?> extractSerial({
    required String romPath,
    required RegExp bootLinePattern,
    required List<ChdmanCandidate> chdmanCandidates,
  }) async {
    final base = p.basenameWithoutExtension(romPath);
    final filenameMatch =
        RegExp(r'\b(S[A-Z]{3,4}[-_]\d{3}[\._]?\d{2})\b', caseSensitive: false)
            .firstMatch(base);
    if (filenameMatch != null) {
      final serial = normalizeSerial(filenameMatch.group(1)!);
      debugPrint('[SerialExtraction] serial from filename: $serial');
      return serial;
    }

    final ext = p.extension(romPath).toLowerCase();
    if (ext == '.chd') {
      final cachedSerial = _readChdSerialMetadata(romPath);
      if (cachedSerial != null) {
        debugPrint('[SerialExtraction] serial from CHD metadata: $cachedSerial');
        return cachedSerial;
      }

      final serial = await _extractSerialFromChd(romPath, bootLinePattern, chdmanCandidates);
      if (serial != null) await _writeChdSerialMetadata(romPath, serial);
      return serial;
    }
    if (ext == '.iso') {
      return _scanSerialFromImage(romPath, bootLinePattern);
    }
    if (ext == '.bin') {
      return _scanSerialFromImage(await _resolveBinDataTrackPath(romPath), bootLinePattern);
    }

    debugPrint('[SerialExtraction] serial could not be determined for: $romPath');
    return null;
  }

  /// Multi-track discs (common for PS1 games with CD-audio soundtracks) are
  /// split into several sibling .bin files, only the first of which — Track
  /// 01, by the Yellow Book standard these consoles use — holds the boot
  /// data. Callers upstream can pass any track as [romPath] (e.g. a
  /// "largest file" heuristic that doesn't know which track is the data
  /// track), so this looks for a sibling .cue sheet referencing [romPath]
  /// and, if found, resolves it to that sheet's first FILE entry instead.
  /// Falls back to [romPath] unchanged if no matching, resolvable .cue
  /// exists — including when the referenced track file isn't actually on
  /// disk — so a genuinely single-track .bin is scanned exactly as before.
  Future<String> _resolveBinDataTrackPath(String romPath) async {
    final dir = io.Directory(p.dirname(romPath));
    final romBasename = p.basename(romPath);
    try {
      await for (final entity in dir.list()) {
        if (entity is! io.File || p.extension(entity.path).toLowerCase() != '.cue') continue;
        final lines = await entity.readAsLines();
        final trackFiles = [
          for (final line in lines)
            RegExp(r'^\s*FILE\s+"([^"]+)"\s+BINARY', caseSensitive: false).firstMatch(line)?.group(1)
        ].whereType<String>().toList();
        if (trackFiles.isEmpty || !trackFiles.any((f) => p.basename(f) == romBasename)) continue;

        final dataTrackPath = p.join(dir.path, p.basename(trackFiles.first));
        if (await io.File(dataTrackPath).exists()) {
          debugPrint('[SerialExtraction] resolved $romBasename to data track via ${entity.path}: $dataTrackPath');
          return dataTrackPath;
        }
        break;
      }
    } catch (_) {}
    return romPath;
  }

  /// Normalises a raw serial string to the standard folder-naming
  /// convention shared by PS1/PS2 tooling.
  /// "SLUS_123.45" → "SLUS-12345", "SLUS-123.45" → "SLUS-12345"
  String normalizeSerial(String raw) {
    var s = raw.toUpperCase().replaceAll('_', '-');
    s = s.replaceAllMapped(RegExp(r'(\d{3})\.(\d{2})'), (m) => '${m[1]}${m[2]}');
    return s;
  }

  /// CHDs need a full chdman extraction to determine their serial, so the
  /// result is cached under this key (rather than a sidecar file next to
  /// the CHD) so it works even when the ROM directory is read-only, e.g. a
  /// network share or some EmuDeck/Steam Deck mounts.
  String _cacheKey(String chdPath) => 'disc_serial_${p.absolute(chdPath)}';

  String? _readChdSerialMetadata(String chdPath) {
    final value = _prefs.getString(_cacheKey(chdPath))?.trim();
    if (value != null && RegExp(r'^S[A-Z]{3,4}-\d{5}$', caseSensitive: false).hasMatch(value)) {
      return normalizeSerial(value);
    }
    return null;
  }

  Future<void> _writeChdSerialMetadata(String chdPath, String serial) async {
    try {
      await _prefs.setString(_cacheKey(chdPath), serial);
    } catch (error) {
      debugPrint('[SerialExtraction] could not cache CHD serial: $error');
    }
  }

  Future<String?> _extractSerialFromChd(
    String chdPath,
    RegExp bootLinePattern,
    List<ChdmanCandidate> chdmanCandidates,
  ) async {
    final tempDirectory = await io.Directory.systemTemp.createTemp('freegosy_chd_');
    final chdman = await _findChdmanExecutable(chdmanCandidates);
    if (chdman == null) {
      await tempDirectory.delete(recursive: true);
      debugPrint('[SerialExtraction] chdman was not found beside Freegosy or on PATH');
      return null;
    }
    // Only extractdvd/extractraw support --inputbytes, so those are tried
    // first with a small bounded range (fast, no full-disc extraction).
    // extractcd has no partial-read support, so it — and an unbounded
    // extractdvd/extractraw retry — are kept as full-extraction fallbacks
    // for discs where the boot files sit further into the image.
    final extractionModes = <({String command, String extension, int? maxBytes})>[
      (command: 'extractdvd', extension: 'iso', maxBytes: _headerScanBytes),
      (command: 'extractdvd', extension: 'iso', maxBytes: null),
      (command: 'extractcd', extension: 'iso', maxBytes: null),
      (command: 'extractraw', extension: 'raw', maxBytes: null),
    ];

    try {
      for (var i = 0; i < extractionModes.length; i++) {
        final mode = extractionModes[i];
        final extractedPath = p.join(tempDirectory.path, 'disc_$i.${mode.extension}');
        try {
          final result = await io.Process.run(chdman, [
            mode.command,
            '-i',
            chdPath,
            '-o',
            extractedPath,
            if (mode.maxBytes != null) ...['--inputbytes', '${mode.maxBytes}'],
          ]);
          if (result.exitCode != 0) {
            debugPrint(
              '[SerialExtraction] chdman ${mode.command} '
              '(maxBytes=${mode.maxBytes}) failed: ${result.stderr}',
            );
            continue;
          }
          final serial = await _scanSerialFromImage(extractedPath, bootLinePattern,
              maxScanBytes: mode.maxBytes);
          if (serial != null) return serial;
        } catch (error) {
          debugPrint('[SerialExtraction] chdman ${mode.command} failed: $error');
        } finally {
          try {
            await io.File(extractedPath).delete();
          } catch (_) {}
        }
      }
    } catch (error) {
      debugPrint('[SerialExtraction] chdman is unavailable or failed: $error');
    } finally {
      try {
        await tempDirectory.delete(recursive: true);
      } catch (error) {
        debugPrint('[SerialExtraction] could not clean up temp dir ${tempDirectory.path}: $error');
      }
    }
    return null;
  }

  Future<String?> _findChdmanExecutable(List<ChdmanCandidate> chdmanCandidates) async {
    final executableName = _platform.isWindows ? 'chdman.exe' : 'chdman';
    final candidateDirectories = <String>{};
    try {
      candidateDirectories.add(io.File(io.Platform.resolvedExecutable).parent.path);
    } catch (_) {}

    candidateDirectories.add(io.Directory.current.path);

    for (final candidate in chdmanCandidates) {
      try {
        final exePath =
            await _directoryService.findEmulatorExecutable(candidate.emulatorId, candidate.exeName);
        if (exePath != null) {
          final entity = io.FileSystemEntity.typeSync(exePath);
          candidateDirectories.add(
              entity == io.FileSystemEntityType.directory ? exePath : io.File(exePath).parent.path);
        }
      } catch (_) {}
    }

    // chdman ships alongside the main executable in MAME's official "tools"
    // distribution (and in most Linux/macOS package-manager MAME builds), so
    // a user's existing MAME install is also worth checking regardless of
    // which console this serial extraction is for.
    try {
      final mameExeName = _platform.isWindows ? 'mame.exe' : 'mame';
      final mamePath = await _directoryService.findEmulatorExecutable('mame', mameExeName);
      if (mamePath != null) {
        final entity = io.FileSystemEntity.typeSync(mamePath);
        candidateDirectories
            .add(entity == io.FileSystemEntityType.directory ? mamePath : io.File(mamePath).parent.path);
      }
    } catch (_) {}

    for (final directory in candidateDirectories) {
      final candidate = p.join(directory, executableName);
      if (await io.File(candidate).exists()) {
        debugPrint('[SerialExtraction] using chdman: $candidate');
        return candidate;
      }
    }

    debugPrint('[SerialExtraction] chdman not found beside app or configured emulators; trying PATH');
    return executableName;
  }

  /// Scans [imagePath] for [bootLinePattern]. [maxScanBytes] bounds how much
  /// of the file gets read — pass null (the default) to scan to EOF, which
  /// is what a fully-extracted (or user-supplied, non-CHD) image needs: an
  /// ISO9660 root directory can be placed anywhere on the disc, so nothing
  /// short of scanning the whole file is guaranteed to find it. Only the
  /// CHD path's first, deliberately-small extraction attempt passes a
  /// bound, matching how much was actually extracted (see
  /// _extractSerialFromChd) — every subsequent, fully-extracted fallback
  /// mode must scan everything it just paid to extract, or that fallback
  /// is pointless.
  Future<String?> _scanSerialFromImage(String imagePath, RegExp bootLinePattern,
      {int? maxScanBytes}) async {
    io.RandomAccessFile? file;
    try {
      file = await io.File(imagePath).open(mode: io.FileMode.read);
      // Scan in overlapping chunks so the boot line is found regardless of
      // its byte offset within the scanned range.
      const chunkSize = 1024 * 1024;
      const overlap = 256;
      final length = await file.length();
      final scanLimit = maxScanBytes == null ? length : (maxScanBytes < length ? maxScanBytes : length);
      var offset = 0;
      while (offset < scanLimit) {
        await file.setPosition(offset);
        final bytes = await file.read((length - offset).clamp(0, chunkSize));
        final text = latin1.decode(bytes, allowInvalid: true);
        final bootMatch = bootLinePattern.firstMatch(text);
        if (bootMatch != null) {
          final serial = normalizeSerial(bootMatch.group(1)!);
          debugPrint('[SerialExtraction] serial from boot line: $serial');
          return serial;
        }
        if (bytes.length < chunkSize) break;
        offset += chunkSize - overlap;
      }
    } catch (_) {
    } finally {
      if (file != null) await file.close();
    }

    debugPrint('[SerialExtraction] serial could not be determined for: $imagePath');
    return null;
  }
}
