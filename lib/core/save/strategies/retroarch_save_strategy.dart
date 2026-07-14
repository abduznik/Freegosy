import 'dart:io' as io;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import '../../platform/platform_info.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';
import 'package:path/path.dart' as p; // Import path package

/// Save strategy for RetroArch emulator.
///
/// Save files live next to RetroArch.exe in saves/{coreName}/.
/// Core name mapping is derived from the platform slug.
class RetroArchSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;
  final PlatformInfo _platform;
  String _ndsCore = 'melonds'; // Default NDS core
  String? _cachedSaveRoot; // Cached from retroarch.cfg

  // Test-only override to skip reading the real retroarch.cfg.
  @visibleForTesting
  bool skipConfigRead = false;

  RetroArchSaveStrategy(this._directoryService, {PlatformInfo? platform})
      : _platform = platform ?? PlatformInfo.current;

  void setNdsCore(String core) {
    _ndsCore = core;
  }

  /// Per-platform core overrides (slug -> coreId). Set from StrategyRegistry.
  final Map<String, String> _coreOverrides = {};

  void loadCoreOverrides(Map<String, String> overrides) {
    _coreOverrides
      ..clear()
      ..addAll(overrides);
  }

  /// Resolves the core info for a slug, checking overrides first.
  _CoreInfo? _getCoreInfo(String slug) {
    // 1. NDS dynamic override (backward compat)
    if (slug == 'nds' || slug == 'nintendo-ds') {
      return _ndsCore == 'desmume'
          ? const _CoreInfo('desmume2015_libretro', 'NDS', 'States/NDS')
          : const _CoreInfo('melonds_libretro', 'NDS', 'States/NDS');
    }

    // 2. General core override from registry
    final overrideCoreId = _coreOverrides[slug];
    if (overrideCoreId != null) {
      final baseName = overrideCoreId.replaceAll(RegExp(r'\.(dll|so|dylib)$'), '');
      // Try to find matching _coreMap entry by coreName
      for (final entry in _coreMap.entries) {
        if (entry.value.coreName == baseName) {
          return entry.value;
        }
      }
      // Fallback: use the override core name with generic save folders
      return _CoreInfo(baseName, baseName, 'States/$baseName');
    }

    // 3. Default from static map
    return _coreMap[slug];
  }

  @override
  String get strategyId => 'retroarch';

  @override
  bool get shouldZip => false;

  // _CoreInfo maps platform slugs to RetroArch core info, including save and state directories.
  static const Map<String, _CoreInfo> _coreMap = {
    // Nintendo
    'gba':       _CoreInfo('mgba_libretro',            'mGBA',               'mGBA'),
    'gbc':       _CoreInfo('mgba_libretro',            'mGBA',               'mGBA'),
    'gb':        _CoreInfo('mgba_libretro',            'mGBA',               'mGBA'),
    'nes':       _CoreInfo('fceumm_libretro',          'NES',                'States/NES'),
    'snes':      _CoreInfo('snes9x_libretro',          'Snes9x',             'Snes9x'),
    'n64':       _CoreInfo('mupen64plus_next_libretro', 'N64',                'States/N64'),
    'nds':       _CoreInfo('melonds_libretro',         'NDS',                'States/NDS'),
    'nintendo-ds': _CoreInfo('melonds_libretro',       'NDS',                'States/NDS'),
    '3ds':       _CoreInfo('azahar_libretro',          '3DS',                'States/3DS'),
    'n3ds':      _CoreInfo('azahar_libretro',          '3DS',                'States/3DS'),
    'nintendo-3ds': _CoreInfo('azahar_libretro',       '3DS',                'States/3DS'),
    'virtualboy': _CoreInfo('mednafen_vb_libretro',    'Virtual Boy',        'States/Virtual Boy'),
    // Sony
    'psx':       _CoreInfo('pcsx_rearmed_libretro',    'PCSX-ReARMed',       'PCSX-ReARMed'),
    'ps1':       _CoreInfo('pcsx_rearmed_libretro',    'PCSX-ReARMed',       'PCSX-ReARMed'),
    'playstation': _CoreInfo('pcsx_rearmed_libretro',  'PCSX-ReARMed',       'PCSX-ReARMed'),
    'psp':       _CoreInfo('ppsspp_libretro',          'PPSSPP/PSP/SAVEDATA', 'PPSSPP'),
    'playstation-portable': _CoreInfo('ppsspp_libretro', 'PPSSPP/PSP/SAVEDATA', 'PPSSPP'),
    'ps2':       _CoreInfo('pcsx2_libretro',           'PCSX2',              'States/PCSX2'),
    // Sega
    'megadrive': _CoreInfo('genesis_plus_gx_libretro', 'Mega Drive',         'States/Mega Drive'),
    'genesis':   _CoreInfo('genesis_plus_gx_libretro', 'Mega Drive',         'States/Mega Drive'),
    'md':        _CoreInfo('genesis_plus_gx_libretro', 'Mega Drive',         'States/Mega Drive'),
    'segacd':    _CoreInfo('genesis_plus_gx_libretro', 'Sega CD',            'States/Sega CD'),
    'sms':       _CoreInfo('genesis_plus_gx_libretro', 'Sega Master System', 'States/Sega Master System'),
    'mastersystem': _CoreInfo('genesis_plus_gx_libretro', 'Sega Master System', 'States/Sega Master System'),
    'gamegear':  _CoreInfo('genesis_plus_gx_libretro', 'Game Gear',          'States/Game Gear'),
    'saturn':    _CoreInfo('mednafen_saturn_libretro', 'Saturn',             'States/Saturn'),
    'dc':        _CoreInfo('flycast_libretro',         'Dreamcast',          'States/Dreamcast'),
    'dreamcast': _CoreInfo('flycast_libretro',         'Dreamcast',          'States/Dreamcast'),
    // Atari
    'atari2600': _CoreInfo('stella_libretro',          'Atari 2600',         'States/Atari 2600'),
    'atari7800': _CoreInfo('prosystem_libretro',       'Atari 7800',         'States/Atari 7800'),
    'atari5200': _CoreInfo('atari800_libretro',        'Atari 800',          'States/Atari 800'),
    'atari800':  _CoreInfo('atari800_libretro',        'Atari 800',          'States/Atari 800'),
    'lynx':      _CoreInfo('mednafen_lynx_libretro',   'Lynx',               'States/Lynx'),
    // Arcade / SNK
    'neogeo':    _CoreInfo('fbneo_libretro',           'FinalBurn Neo',      'States/FinalBurn Neo'),
    'arcade':    _CoreInfo('fbneo_libretro',           'FinalBurn Neo',      'States/FinalBurn Neo'),
    'mame':      _CoreInfo('mame_libretro',            'MAME',               'States/MAME'),
    // NEC
    'pcengine':  _CoreInfo('mednafen_pce_libretro',    'PCE',                'States/PCE'),
    'pcenginecd': _CoreInfo('mednafen_pce_libretro',   'PCE',                'States/PCE'),
    'supergrafx': _CoreInfo('mednafen_supergrafx_libretro', 'SuperGrafx',    'States/SuperGrafx'),
    'pcfx':      _CoreInfo('mednafen_pcfx_libretro',   'PC-FX',              'States/PC-FX'),
    // Bandai
    'wonderswan': _CoreInfo('mednafen_wswan_libretro', 'WonderSwan',         'States/WonderSwan'),
    'wonderswancolor': _CoreInfo('mednafen_wswan_libretro', 'WonderSwan',    'States/WonderSwan'),
    'ngp':       _CoreInfo('mednafen_ngp_libretro',    'Neo Geo Pocket',     'States/Neo Geo Pocket'),
    'ngpc':      _CoreInfo('mednafen_ngp_libretro',    'Neo Geo Pocket',     'States/Neo Geo Pocket'),
    // Computer
    'dos':       _CoreInfo('dosbox_pure_libretro',     'DOSBox Pure',        'States/DOSBox Pure'),
    'msx':       _CoreInfo('bluemsx_libretro',         'blueMSX',            'States/blueMSX'),
    'c64':       _CoreInfo('vice_x64_libretro',        'VICE',               'States/VICE'),
    'commodore64': _CoreInfo('vice_x64_libretro',      'VICE',               'States/VICE'),
    'amiga':     _CoreInfo('puae_libretro',            'PUAE',               'States/PUAE'),
    'zxspectrum': _CoreInfo('fuse_libretro',           'Fuse',               'States/Fuse'),
    'amstradcpc': _CoreInfo('cap32_libretro',          'Caprice32',          'States/Caprice32'),
    'sharp68000': _CoreInfo('px68k_libretro',          'PX-68K',             'States/PX-68K'),
    'pc98':      _CoreInfo('np2kai_libretro',          'Neko Project II',    'States/Neko Project II'),
    // Other
    'vectrex':   _CoreInfo('vecx_libretro',            'VecX',               'States/VecX'),
  };

  /// Reads `savefile_directory` from retroarch.cfg if available.
  Future<String?> _readConfigSaveRoot() async {
    if (skipConfigRead) return null;
    if (_cachedSaveRoot != null) return _cachedSaveRoot;

    final List<String> candidates = [];

    if (_platform.isMacOS) {
      final home = _platform.environment['HOME'] ?? '';
      candidates.add(p.join(home, 'Library', 'Application Support', 'RetroArch', 'config', 'retroarch.cfg'));
      candidates.add(p.join(home, '.config', 'retroarch', 'retroarch.cfg'));
    } else if (_platform.isLinux) {
      final home = _platform.environment['HOME'] ?? '';
      candidates.add(p.join(home, '.config', 'retroarch', 'retroarch.cfg'));
    } else if (_platform.isWindows) {
      final appData = _platform.environment['APPDATA'] ?? '';
      candidates.add(p.join(appData, 'RetroArch', 'retroarch.cfg'));
    }

    // Also check next to the bundled exe
    final exePath = await _directoryService.findEmulatorExecutable('retroarch', _getRetroArchExe());
    if (exePath != null) {
      String exeDir = _platform.isMacOS
          ? p.join(io.File(exePath).parent.parent.parent.parent.path)
          : io.File(exePath).parent.path;
      if (await io.FileSystemEntity.isDirectory(exePath)) exeDir = exePath;
      candidates.add(p.join(exeDir, 'retroarch.cfg'));
    }

    for (final cfgPath in candidates) {
      final cfgFile = io.File(cfgPath);
      if (!await cfgFile.exists()) continue;
      try {
        final lines = await cfgFile.readAsLines();
        for (final line in lines) {
          final match = RegExp(r'^\s*savefile_directory\s*=\s*"([^"]*)"').firstMatch(line);
          if (match != null) {
            var dir = match.group(1)!;
            if (dir.startsWith('~')) {
              final home = _platform.environment['HOME'];
              if (home != null) dir = dir.replaceFirst('~', home);
            }
            if (await io.Directory(dir).exists()) {
              _cachedSaveRoot = dir;
              return dir;
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Resolves the save root directory: retroarch.cfg first, then exe-relative.
  Future<String> _resolveSaveRoot() async {
    final cfg = await _readConfigSaveRoot();
    if (cfg != null) return cfg;
    final exePath = await _directoryService.findEmulatorExecutable('retroarch', _getRetroArchExe());
    String exeDir = _platform.isMacOS
        ? p.join(io.File(exePath!).parent.parent.parent.parent.path)
        : io.File(exePath!).parent.path;
    if (await io.FileSystemEntity.isDirectory(exePath)) exeDir = exePath;
    return p.join(exeDir, 'saves');
  }

  String _getRetroArchExe() {
    if (_platform.isWindows) return 'RetroArch.exe';
    if (_platform.isMacOS) return 'RetroArch.app/Contents/MacOS/RetroArch';
    return 'retroarch';
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final slug = game.platformSlug?.toLowerCase() ?? '';
    final coreInfo = _getCoreInfo(slug);

    if (coreInfo == null) return null;

    if (_platform.isLinux) {
      final baseDir = await _directoryService.getEmulatorAppSupportDirectory('retroarch', platformSlug: slug);

      if (_directoryService.linuxSyncPreset == 'emudeck' || baseDir.contains('Emulation/saves')) {
        // EmuDeck structure: Emulation/saves/retroarch/saves/CoreName
        if (p.basename(baseDir) == 'saves') {
          return p.join(baseDir, coreInfo.saveFolder);
        }
        return p.join(baseDir, 'saves', coreInfo.saveFolder);
      }

      // EmuDeck mapping returns the folder containing the actual saves
      return p.join(baseDir, coreInfo.saveFolder);
    }

    final saveRoot = await _resolveSaveRoot();
    return p.join(saveRoot, coreInfo.saveFolder);
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final map = await getSaveFilesWithScreenshots(game, romPath, sessionStart: sessionStart, syncMode: syncMode);
    return map.keys.toList();
  }

  @override
  Future<Map<io.File, io.File?>> getSaveFilesWithScreenshots(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final slug = game.platformSlug?.toLowerCase() ?? '';
    final coreInfo = _getCoreInfo(slug);

    if (coreInfo == null) return {};

    String? rootSaveDir;
    String? statesRoot;

    if (_platform.isLinux) {
      rootSaveDir = await getSaveDir(game, romPath);
      final baseDir = await _directoryService.getEmulatorAppSupportDirectory('retroarch', platformSlug: slug);

      if (_directoryService.linuxSyncPreset == 'emudeck') {
        // EmuDeck: saves are in Emulation/saves/retroarch, states in Emulation/states/retroarch
        // baseDir is .../Emulation/saves/retroarch
        final emulationRoot = p.dirname(p.dirname(baseDir));
        statesRoot = p.join(emulationRoot, 'states', 'retroarch', coreInfo.statesFolder);
      } else if (_directoryService.linuxSyncPreset == 'retrodeck') {
        // RetroDECK: baseDir is .../retroarch/
        statesRoot = p.join(baseDir, 'states', coreInfo.statesFolder);
      } else {
        statesRoot = p.join(p.dirname(baseDir), 'states', coreInfo.statesFolder);
      }
    } else {
      rootSaveDir = await getSaveDir(game, romPath);

      // States use the same root but under a states/ subfolder
      final saveRoot = await _resolveSaveRoot();
      statesRoot = p.join(io.Directory(saveRoot).parent.path, 'states', coreInfo.statesFolder);
    }

    if (rootSaveDir == null) return {};

    final stem = getRomStem(game);
    final List<io.File> filesToCheck = [];

    // Special case for PSP saves
    if (slug == 'psp' || slug == 'playstation-portable') {
      if (syncMode == 'saves' || syncMode == 'both') {
        final pspDir = io.Directory(rootSaveDir);
        if (await pspDir.exists()) {
          bool hasFiles = false;
          await for (final _ in pspDir.list(recursive: true)) {
            hasFiles = true;
            break;
          }
          if (hasFiles) {
            filesToCheck.add(io.File(rootSaveDir));
          }
        }
      }
    } else {
      if (syncMode == 'saves' || syncMode == 'both') {
        final savesDirObj = io.Directory(rootSaveDir);
        if (await savesDirObj.exists()) {
          final stemLower = stem.toLowerCase();
          bool found = false;
          await for (final entity in savesDirObj.list()) {
            if (entity is! io.File) continue;
            final fname = p.basename(entity.path).toLowerCase();
            if (fname.startsWith(stemLower) && (fname.endsWith('.srm') || fname.endsWith('.sav') || fname.endsWith('.mcd'))) {
              filesToCheck.add(entity);
              found = true;
              break;
            }
          }
          if (!found) {
            await for (final entity in savesDirObj.list()) {
              if (entity is! io.File) continue;
              final fname = p.basename(entity.path).toLowerCase();
              if (fname.endsWith('.srm') || fname.endsWith('.sav') || fname.endsWith('.mcd')) {
                final stemWords = stemLower
                    .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
                    .split(' ')
                    .where((w) => w.length >= 3)
                    .toList();
                if (stemWords.any((word) => fname.contains(word))) {
                  filesToCheck.add(entity);
                  found = true;
                  break;
                }
              }
            }
          }
          if (!found) {
            // Last resort: scan directory for ANY .srm/.sav file
            await for (final entity in savesDirObj.list()) {
              if (entity is! io.File) continue;
              final fname = p.basename(entity.path).toLowerCase();
              if (fname.endsWith('.srm') || fname.endsWith('.sav') || fname.endsWith('.mcd')) {
                filesToCheck.add(entity);
                found = true;
                break;
              }
            }
            if (!found) {
              filesToCheck.add(io.File(p.join(rootSaveDir, '$stem.srm')));
            }
          }
        } else {
          filesToCheck.add(io.File(p.join(rootSaveDir, '$stem.srm')));
        }
      }
    }

    // Handle States
    if ((syncMode == 'states' || syncMode == 'both')) {
      final romStem = io.File(romPath).uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      for (final checkStem in [stem, romStem]) {
        filesToCheck.add(io.File('$statesRoot/$checkStem.state.auto'));
        for (int i = 0; i <= 9; i++) {
          filesToCheck.add(io.File('$statesRoot/$checkStem.state$i'));
        }
      }
    }

    // Filter out non-existent files and apply sessionStart filter
    final finalResult = <io.File, io.File?>{};
    for (final f in filesToCheck) {
      final existsAsFile = await f.exists();
      final existsAsDir = await io.Directory(f.path).exists();
      if (!existsAsFile && !existsAsDir) continue;
      if (sessionStart != null && existsAsFile) {
        final stat = await f.stat();
        if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
      }

      // Check for screenshots if it's a state file
      io.File? screenshot;
      if (f.path.contains('.state')) {
        final screenshotPath = '${f.path}.png';
        final screenFile = io.File(screenshotPath);
        if (await screenFile.exists()) {
          screenshot = screenFile;
        }
      }

      finalResult[f] = screenshot;
    }
    return finalResult;
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final slug = game.platformSlug?.toLowerCase() ?? '';
      final coreInfo = _getCoreInfo(slug);

      if (coreInfo == null) return false;

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final file in archive) {
          if (!file.isFile) continue;
          if (file.name == 'freegosy_sync.txt') continue;

          final isFileState = file.name.contains('.state');
          String? fileTargetDir;
          if (_platform.isLinux) {
            final baseDir = await _directoryService.getEmulatorAppSupportDirectory('retroarch', platformSlug: slug);
            if (_directoryService.linuxSyncPreset == 'emudeck') {
              if (isFileState) {
                final emulationRoot = p.dirname(p.dirname(baseDir));
                fileTargetDir = p.join(emulationRoot, 'states', 'retroarch', coreInfo.statesFolder);
              } else {
                fileTargetDir = p.join(baseDir, coreInfo.saveFolder);
              }
            } else if (_directoryService.linuxSyncPreset == 'retrodeck') {
              fileTargetDir = isFileState
                  ? p.join(baseDir, 'states', coreInfo.statesFolder)
                  : p.join(baseDir, 'saves', coreInfo.saveFolder);
            } else {
              fileTargetDir = isFileState
                  ? p.join(p.dirname(baseDir), 'states', coreInfo.statesFolder)
                  : p.join(baseDir, coreInfo.saveFolder);
            }
          } else {
            final saveRoot = await _resolveSaveRoot();
            fileTargetDir = isFileState
                ? p.join(io.Directory(saveRoot).parent.path, 'states', coreInfo.statesFolder)
                : p.join(saveRoot, coreInfo.saveFolder);
          }
          final dir = io.Directory(fileTargetDir);
          if (!await dir.exists()) await dir.create(recursive: true);

          String targetFilename = file.name;
          if (!isFileState && file.name.toLowerCase().endsWith('.sav')) {
            targetFilename = '${p.basenameWithoutExtension(file.name)}.srm';
          }

          final targetPath = p.normalize(p.join(fileTargetDir, targetFilename));
          await backupSave(targetPath);
          await io.File(targetPath).writeAsBytes(file.content);
        }
        return true;
      }

      String? targetDir;
      final isState = filename.contains('.state');

      if (_platform.isLinux) {
        final baseDir = await _directoryService.getEmulatorAppSupportDirectory('retroarch', platformSlug: slug);

        if (_directoryService.linuxSyncPreset == 'emudeck') {
          if (isState) {
            final emulationRoot = p.dirname(p.dirname(baseDir));
            targetDir = p.join(emulationRoot, 'states', 'retroarch', coreInfo.statesFolder);
          } else {
            targetDir = p.join(baseDir, coreInfo.saveFolder);
          }
        } else if (_directoryService.linuxSyncPreset == 'retrodeck') {
          targetDir = isState
              ? p.join(baseDir, 'states', coreInfo.statesFolder)
              : p.join(baseDir, 'saves', coreInfo.saveFolder);
        } else {
          targetDir = isState
              ? p.join(p.dirname(baseDir), 'states', coreInfo.statesFolder)
              : p.join(baseDir, coreInfo.saveFolder);
        }
      } else {
        final saveRoot = await _resolveSaveRoot();
        targetDir = isState
            ? p.join(io.Directory(saveRoot).parent.path, 'states', coreInfo.statesFolder)
            : p.join(saveRoot, coreInfo.saveFolder);
      }

      final dir = io.Directory(targetDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      // Handle .sav to .srm renaming for RetroArch NDS cores
      String targetFilename = filename;
      if (!isState && filename.toLowerCase().endsWith('.sav')) {
        targetFilename = '${p.basenameWithoutExtension(filename)}.srm';
      }

      final targetPath = p.normalize(p.join(targetDir, targetFilename));
      await backupSave(targetPath); // Backup existing file
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}

class _CoreInfo {
  final String coreName;
  final String saveFolder;
  final String statesFolder;
  const _CoreInfo(this.coreName, this.saveFolder, this.statesFolder);
}
