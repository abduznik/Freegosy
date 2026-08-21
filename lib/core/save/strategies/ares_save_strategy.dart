import 'dart:io' as io;
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../platform/platform_info.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Confirmed battery-save extensions (sync these).
const _batterySaveExtensions = {'.ram', '.eeprom', '.flash', '.chr'};

/// RTC extension — world clock data, not player progress. Do not sync.
const _rtcExtension = '.rtc';

/// State file extensions — never sync as saves (save-state slots .bs1-.bs9).
bool _isStateExtension(String ext) {
  if (ext == _rtcExtension) return true;
  if (RegExp(r'^\.bs[1-9]$').hasMatch(ext)) return true;
  return false;
}

/// Per-platform: confirmed battery-save extensions.
/// Empty set = log-only bucket (no confirmed extensions yet).
const Map<String, Set<String>> _confirmedExtensionsPerPlatform = {
  // Confirmed
  'Famicom':              {'.ram', '.eeprom', '.chr'},
  'Game Boy':             {'.ram', '.eeprom', '.flash'},
  'Game Boy Color':       {'.ram', '.eeprom', '.flash'},
  'Game Boy Advance':     {'.ram', '.eeprom', '.flash'},
  'Mega Drive':           {'.ram', '.eeprom'},
  'Nintendo 64':          {'.ram', '.eeprom', '.flash'},
  // Defaulting to common set — flag for user testing
  'Super Famicom':        {'.ram', '.eeprom', '.flash'},
  'WonderSwan':           {'.ram', '.eeprom', '.flash'},
  'WonderSwan Color':     {'.ram', '.eeprom', '.flash'},
  'Neo Geo Pocket':       {'.ram', '.eeprom'},
  'Neo Geo Pocket Color': {'.ram', '.eeprom'},
  'MSX':                  {'.ram', '.eeprom'},
  // Log-only / unconfirmed — empty set means "log everything"
  'Mega CD':              {},
  'PlayStation':          {},
  'Saturn':               {},
  'PC Engine':            {},
  'Neo Geo':              {},
  'ColecoVision':         {},
  'ZX Spectrum':          {},
  'Atari 2600':           {},
  'SG-1000':              {},
  'SC-3000':              {},
  'Master System':        {},
  'Game Gear':            {},
  'MSX2':                 {},
};

/// Returns the set of battery-save extensions for a platform.
/// For unknown or log-only platforms, returns the common set.
Set<String> _getSaveExtensionsForPlatform(String platformName) {
  final confirmed = _confirmedExtensionsPerPlatform[platformName];
  if (confirmed == null || confirmed.isEmpty) {
    return _batterySaveExtensions;
  }
  return confirmed;
}

/// Whether a platform is in the log-only bucket.
bool _isLogOnlyPlatform(String platformName) {
  final confirmed = _confirmedExtensionsPerPlatform[platformName];
  return confirmed != null && confirmed.isEmpty;
}

/// Save strategy for Ares emulator.
///
/// Save directory layout:
///   `<AresDataDir>/Saves/<Platform Full Name>/<ROM filename base>.<ext>`
///
/// Extension classification:
///   Battery saves: `.ram`, `.eeprom`, `.flash`, `.chr` (platform-dependent)
///   State files: `.bs1`-`.bs9` (excluded from save sync)
///   RTC: `.rtc` (excluded — world clock, not player progress)
class AresSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;
  final PlatformInfo _platform;

  AresSaveStrategy(this._directoryService, {PlatformInfo? platform})
      : _platform = platform ?? PlatformInfo.current;

  @override
  String get strategyId => 'ares';

  @override
  bool get supportsSaveSync => true;

  @override
  bool get shouldZip => false;

  /// Maps Freegosy platform slugs to Ares save folder names.
  static const Map<String, String> _platformFolderNames = {
    'atari2600':       'Atari 2600',
    'nes':             'Famicom',
    'famicom':         'Famicom',
    'snes':            'Super Famicom',
    'sfc':             'Super Famicom',
    'n64':             'Nintendo 64',
    'gb':              'Game Boy',
    'gbc':             'Game Boy Color',
    'gba':             'Game Boy Advance',
    'gamegear':        'Game Gear',
    'sms':             'Master System',
    'mastersystem':    'Master System',
    'genesis':         'Mega Drive',
    'megadrive':       'Mega Drive',
    'md':              'Mega Drive',
    'segacd':          'Mega CD',
    'psx':             'PlayStation',
    'ps1':             'PlayStation',
    'playstation':     'PlayStation',
    'pce':             'PC Engine',
    'pcengine':        'PC Engine',
    'neogeo':          'Neo Geo',
    'neo-geo':         'Neo Geo',
    'neogeoaes':       'Neo Geo',
    'neogeomvs':       'Neo Geo',
    'neo-geo-aes':     'Neo Geo',
    'neo-geo-mvs':     'Neo Geo',
    'mvs':             'Neo Geo',
    'aes':             'Neo Geo',
    'msx':             'MSX',
    'coleco':          'ColecoVision',
    'colecovision':    'ColecoVision',
    'zxspectrum':      'ZX Spectrum',
    'zx-spectrum':     'ZX Spectrum',
    'wonderswan':      'WonderSwan',
    'wonderswancolor': 'WonderSwan Color',
    'ngp':             'Neo Geo Pocket',
    'ngpc':            'Neo Geo Pocket Color',
    'neo-geo-pocket':  'Neo Geo Pocket',
  };

  String _getExeName() {
    if (_platform.isWindows) return 'ares.exe';
    if (_platform.isMacOS) return 'ares.app/Contents/MacOS/ares';
    return 'ares.AppImage';
  }

  /// Resolves the Ares data directory based on OS.
  /// Returns a path unconditionally — `restoreSave`'s `create(recursive: true)`
  /// will create the directory if it doesn't exist yet (fresh install).
  /// Only returns null if we truly can't determine a home dir.
  Future<String?> _getAresDataDir() async {
    if (_platform.isWindows) {
      final exePath = await _directoryService.findEmulatorExecutable('ares', _getExeName());
      if (exePath != null) {
        final exeDir = io.File(exePath).parent.path;
        // Portable mode: settings.bml next to exe
        if (await io.File(p.join(exeDir, 'settings.bml')).exists()) return exeDir;
        // Non-portable: prefer %LOCALAPPDATA%/ares/ if it exists
        final localAppData = _platform.environment['LOCALAPPDATA'] ?? '';
        if (localAppData.isNotEmpty) {
          final appDataDir = p.join(localAppData, 'ares');
          if (await io.Directory(appDataDir).exists()) return appDataDir;
        }
        // Fallback: exe directory (Ares creates settings.bml there on Windows)
        return exeDir;
      }
    } else if (_platform.isMacOS) {
      final home = _platform.environment['HOME'];
      if (home != null) {
        return p.join(home, 'Library', 'Application Support', 'ares');
      }
    } else if (_platform.isLinux) {
      final home = _platform.environment['HOME'];
      if (home != null) {
        return p.join(home, '.local', 'share', 'ares');
      }
    }
    return null;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final dataDir = await _getAresDataDir();
    if (dataDir == null) return null;

    final folderName = _platformFolderNames[game.platformSlug?.toLowerCase()];
    if (folderName == null) return null;

    final savesDir = p.join(dataDir, 'Saves', folderName);
    if (await io.Directory(savesDir).exists()) return savesDir;
    return null;
  }

  /// Extensions recognized as real save data when found inside an Ares
  /// per-game .zip bundle (e.g. PlayStation memory cards). Ares packages
  /// these together with transient `.state.auto`/`.bs*` entries in a
  /// single `<romStem>.zip`, so the zip itself can't be uploaded as-is —
  /// see [_extractZipSaveEntries].
  static const _zipSaveEntryExtensions = {'.mcd', '.mcr', '.srm', '.sav'};

  /// Extracts confirmed save entries (not state/RTC entries) from an Ares
  /// .zip save bundle into a stable temp path, so they can be synced as
  /// normal files. Returns the extracted files, or an empty list if the
  /// zip contains no recognized save entries.
  Future<List<io.File>> _extractZipSaveEntries(io.File zipFile) async {
    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final extractDir = io.Directory(p.join(p.dirname(zipFile.path), '.freegosy_ares_extract'));
      await extractDir.create(recursive: true);

      final extracted = <io.File>[];
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final entryExt = p.extension(entry.name).toLowerCase();
        if (!_zipSaveEntryExtensions.contains(entryExt)) continue;

        final outFile = io.File(p.join(extractDir.path, p.basename(entry.name)));
        await outFile.writeAsBytes(entry.content as List<int>);
        // Match the zip's own mtime so the sessionStart filter (applied by
        // the caller against these extracted files) behaves the same as it
        // would for a loose save file.
        await outFile.setLastModified((await zipFile.stat()).modified);
        extracted.add(outFile);
      }
      return extracted;
    } catch (e) {
      dev.log('[Ares Save] Failed to extract zip save bundle ${zipFile.path}: $e');
      return [];
    }
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];

    final folderName = _platformFolderNames[game.platformSlug?.toLowerCase()] ?? '';
    final platformExtensions = _getSaveExtensionsForPlatform(folderName);
    final logOnly = _isLogOnlyPlatform(folderName);
    final romStem = getRomStem(game).toLowerCase();

    final dir = io.Directory(saveDir);
    if (!await dir.exists()) return [];

    final result = <io.File>[];
    await for (final entity in dir.list()) {
      if (entity is! io.File) continue;
      final fname = p.basename(entity.path).toLowerCase();
      final ext = p.extension(fname).toLowerCase();
      final fileStem = p.basenameWithoutExtension(fname).toLowerCase();

      // Stem-prefix match: file must start with the ROM stem
      if (!fileStem.startsWith(romStem)) continue;

      // Ares bundles the real save together with transient state files in
      // a single per-game .zip (e.g. PlayStation memory cards) — open it
      // and pull out just the recognized save entries.
      if (ext == '.zip') {
        final zipEntries = await _extractZipSaveEntries(entity);
        for (final f in zipEntries) {
          if (sessionStart != null) {
            final stat = await f.stat();
            if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
          }
          result.add(f);
        }
        continue;
      }

      // Exclude state files and RTC
      if (_isStateExtension(ext)) continue;

      // Check if extension is a known battery-save type
      if (platformExtensions.contains(ext)) {
        // Confirmed save type — sync it
      } else if (logOnly) {
        // Log-only platform — sync common types, log unknowns
        if (!_batterySaveExtensions.contains(ext)) {
          dev.log('[Ares Save] Unknown extension "$ext" for $folderName: ${p.basename(entity.path)}');
          continue;
        }
      } else {
        // Confirmed platform but unrecognized extension — skip
        continue;
      }

      // Session start filter
      if (sessionStart != null) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
      }

      result.add(entity);
    }

    return result;
  }

  @override
  Future<bool> restoreSave(
      Game game, String destPath, Uint8List data, String filename) async {
    try {
      // Compute the save path directly — do NOT use getSaveDir() which
      // returns null when the folder doesn't exist yet (correct for read
      // paths, but restoreSave must CREATE the directory).
      final dataDir = await _getAresDataDir();
      if (dataDir == null) return false;

      final folderName = _platformFolderNames[game.platformSlug?.toLowerCase()];
      if (folderName == null) return false;

      final savesDir = p.join(dataDir, 'Saves', folderName);
      final romStem = p.basenameWithoutExtension(destPath).toLowerCase();
      final ext = p.extension(filename).isNotEmpty ? p.extension(filename) : '.ram';

      // If Ares stores this game's save as a .zip bundle (memory card +
      // state files together, e.g. PlayStation), the incoming save must be
      // injected into that zip — Ares never reads a loose .mcd/.mcr file.
      if (_zipSaveEntryExtensions.contains(ext.toLowerCase())) {
        final zipPath = p.normalize(p.join(savesDir, '$romStem.zip'));
        final zipFile = io.File(zipPath);
        if (await zipFile.exists()) {
          return await _injectIntoZipSaveBundle(zipFile, filename, data);
        }
      }

      final targetPath = p.normalize(p.join(savesDir, '$romStem$ext'));
      await io.Directory(p.dirname(targetPath)).create(recursive: true);
      await backupSave(targetPath);
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Replaces (or adds) the entry named [entryName] inside [zipFile] with
  /// [data], preserving every other entry (e.g. `.state.auto`) untouched.
  Future<bool> _injectIntoZipSaveBundle(io.File zipFile, String entryName, Uint8List data) async {
    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final newArchive = Archive();
      var replaced = false;
      for (final entry in archive) {
        if (!entry.isFile) continue;
        if (p.basename(entry.name) == entryName) {
          newArchive.addFile(ArchiveFile(entry.name, data.length, data));
          replaced = true;
        } else {
          newArchive.addFile(ArchiveFile(entry.name, entry.size, entry.content));
        }
      }
      if (!replaced) {
        newArchive.addFile(ArchiveFile(entryName, data.length, data));
      }

      await backupSave(zipFile.path);
      final encoded = ZipEncoder().encode(newArchive);
      await zipFile.writeAsBytes(encoded);
      return true;
    } catch (e) {
      dev.log('[Ares Save] Failed to inject save into zip bundle ${zipFile.path}: $e');
      return false;
    }
  }
}
