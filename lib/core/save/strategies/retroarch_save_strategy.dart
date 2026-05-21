import 'dart:io' as io;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

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
  String _ndsCore = 'melonds'; // Default NDS core
  String? _cachedSaveRoot; // Cached from retroarch.cfg

  // Test-only override to skip reading the real retroarch.cfg.
  @visibleForTesting
  bool skipConfigRead = false;

  RetroArchSaveStrategy(this._directoryService);

  void setNdsCore(String core) {
    _ndsCore = core;
  }

  @override
  String get strategyId => 'retroarch';

  @override
  bool get shouldZip => false;

  // _CoreInfo maps platform slugs to RetroArch core info, including save and state directories.
  static const Map<String, _CoreInfo> _coreMap = {
    'gba':       _CoreInfo('mgba_libretro',            'mGBA',               'mGBA'),
    'gbc':       _CoreInfo('mgba_libretro',            'mGBA',               'mGBA'), // mGBA uses the same save folder for GBA/GBC/GB
    'gb':        _CoreInfo('mgba_libretro',            'mGBA',               'mGBA'),
    'snes':      _CoreInfo('snes9x_libretro',          'Snes9x',             'Snes9x'),
    'nes':       _CoreInfo('fceumm_libretro',          'NES',                'States/NES'),
    'n64':       _CoreInfo('mupen64plus_next_libretro', 'N64',                'States/N64'),
    'nds':       _CoreInfo('desmume2015_libretro',     'NDS',                'States/NDS'),
    'psx':       _CoreInfo('pcsx_rearmed_libretro',    'PCSX-ReARMed',       'PCSX-ReARMed'),
    'psp':       _CoreInfo('ppsspp_libretro',          'PPSSPP/PSP/SAVEDATA', 'PPSSPP'), // Note: saveFolder is 'PPSSPP/PSP/SAVEDATA', statesFolder is 'PPSSPP'
    'playstation': _CoreInfo('pcsx_rearmed_libretro', 'PCSX-ReARMed', 'PCSX-ReARMed'), // Assuming this is also PSX and needs save/state dir logic
    'playstation-portable': _CoreInfo('ppsspp_libretro', 'PPSSPP/PSP/SAVEDATA', 'PPSSPP'), // Alias for PSP
    'dreamcast': _CoreInfo('flycast_libretro',         'Dreamcast',          'States/Dreamcast'),
    'dc':        _CoreInfo('flycast_libretro',         'Dreamcast',          'States/Dreamcast'), // Alias for Dreamcast
    'megadrive': _CoreInfo('genesis_plus_gx_libretro', 'Mega Drive',         'States/Mega Drive'),
    'genesis':   _CoreInfo('genesis_plus_gx_libretro', 'Mega Drive',         'States/Mega Drive'), // Alias for Mega Drive
    'md':        _CoreInfo('genesis_plus_gx_libretro', 'Mega Drive',         'States/Mega Drive'), // Alias for Mega Drive
  };

  /// Reads `savefile_directory` from retroarch.cfg if available.
  Future<String?> _readConfigSaveRoot() async {
    if (skipConfigRead) return null;
    if (_cachedSaveRoot != null) return _cachedSaveRoot;

    final List<String> candidates = [];

    if (io.Platform.isMacOS) {
      final home = io.Platform.environment['HOME'] ?? '';
      candidates.add(p.join(home, 'Library', 'Application Support', 'RetroArch', 'config', 'retroarch.cfg'));
      candidates.add(p.join(home, '.config', 'retroarch', 'retroarch.cfg'));
    } else if (io.Platform.isLinux) {
      final home = io.Platform.environment['HOME'] ?? '';
      candidates.add(p.join(home, '.config', 'retroarch', 'retroarch.cfg'));
    } else if (io.Platform.isWindows) {
      final appData = io.Platform.environment['APPDATA'] ?? '';
      candidates.add(p.join(appData, 'RetroArch', 'retroarch.cfg'));
    }

    // Also check next to the bundled exe
    final exePath = await _directoryService.findEmulatorExecutable('retroarch', _getRetroArchExe());
    if (exePath != null) {
      String exeDir = io.Platform.isMacOS
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
              final home = io.Platform.environment['HOME'];
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
    String exeDir = io.Platform.isMacOS
        ? p.join(io.File(exePath!).parent.parent.parent.parent.path)
        : io.File(exePath!).parent.path;
    if (await io.FileSystemEntity.isDirectory(exePath)) exeDir = exePath;
    return p.join(exeDir, 'saves');
  }

  String _getRetroArchExe() {
    if (io.Platform.isWindows) return 'RetroArch.exe';
    if (io.Platform.isMacOS) return 'RetroArch.app/Contents/MacOS/RetroArch';
    return 'retroarch';
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final slug = game.platformSlug?.toLowerCase() ?? '';
    _CoreInfo? coreInfo = _coreMap[slug];

    // Dynamic override for NDS based on user preference
    if (slug == 'nds' || slug == 'nintendo-ds') {
      coreInfo = _ndsCore == 'desmume'
          ? const _CoreInfo('desmume2015_libretro', 'NDS', 'States/NDS')
          : const _CoreInfo('melonds_libretro', 'NDS', 'States/NDS');
    }

    if (coreInfo == null) return null;

    if (io.Platform.isLinux) {
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
    _CoreInfo? coreInfo = _coreMap[slug];

    // Dynamic override for NDS based on user preference
    if (slug == 'nds' || slug == 'nintendo-ds') {
      coreInfo = _ndsCore == 'desmume'
          ? const _CoreInfo('desmume2015_libretro', 'NDS', 'States/NDS')
          : const _CoreInfo('melonds_libretro', 'NDS', 'States/NDS');
    }

    if (coreInfo == null) return {};

    String? rootSaveDir;
    String? statesRoot;

    if (io.Platform.isLinux) {
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
        if (stat.modified.isBefore(sessionStart)) continue;
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
      _CoreInfo? coreInfo = _coreMap[slug];

      // Dynamic override for NDS based on user preference
      if (slug == 'nds' || slug == 'nintendo-ds') {
        coreInfo = _ndsCore == 'desmume'
            ? const _CoreInfo('desmume2015_libretro', 'NDS', 'States/NDS')
            : const _CoreInfo('melonds_libretro', 'NDS', 'States/NDS');
      }

      if (coreInfo == null) return false;

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final file in archive) {
          if (!file.isFile) continue;
          if (file.name == 'freegosy_sync.txt') continue;

          final isFileState = file.name.contains('.state');
          String? fileTargetDir;
          if (io.Platform.isLinux) {
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

      if (io.Platform.isLinux) {
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
