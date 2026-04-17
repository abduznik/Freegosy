import 'dart:io' as io;
import 'dart:typed_data';

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

  RetroArchSaveStrategy(this._directoryService);

  void setNdsCore(String core) {
    _ndsCore = core;
  }

  @override
  String get strategyId => 'retroarch';

  // _CoreInfo maps platform slugs to RetroArch core info, including save and state directories.
  static const Map<String, _CoreInfo> _coreMap = {
    'gba':       _CoreInfo('mgba_libretro',            'mGBA',               'mGBA'),
    'gbc':       _CoreInfo('mgba_libretro',            'mGBA',               'mGBA'), // mGBA uses the same save folder for GBA/GBC/GB
    'gb':        _CoreInfo('mgba_libretro',            'mGBA',               'mGBA'),
    'snes':      _CoreInfo('snes9x_libretro',          'SNES',               'States/SNES'),
    'nes':       _CoreInfo('fceumm_libretro',          'NES',                'States/NES'),
    'n64':       _CoreInfo('mupen64plus_next_libretro', 'N64',                'States/N64'),
    'nds':       _CoreInfo('desmume2015_libretro',     'NDS',                'States/NDS'),
    'psx':       _CoreInfo('pcsx_rearmed_libretro',    'PSX',                'States/PSX'),
    'psp':       _CoreInfo('ppsspp_libretro',          'PPSSPP/PSP/SAVEDATA', 'PPSSPP'), // Note: saveFolder is 'PPSSPP/PSP/SAVEDATA', statesFolder is 'PPSSPP'
    'playstation': _CoreInfo('pcsx_rearmed_libretro', 'PCSX-ReARMed', 'PCSX-ReARMed'), // Assuming this is also PSX and needs save/state dir logic
    'playstation-portable': _CoreInfo('ppsspp_libretro', 'PPSSPP/PSP/SAVEDATA', 'PPSSPP'), // Alias for PSP
    'dreamcast': _CoreInfo('flycast_libretro',         'Dreamcast',          'States/Dreamcast'),
    'dc':        _CoreInfo('flycast_libretro',         'Dreamcast',          'States/Dreamcast'), // Alias for Dreamcast
    'megadrive': _CoreInfo('genesis_plus_gx_libretro', 'Mega Drive',         'States/Mega Drive'),
    'genesis':   _CoreInfo('genesis_plus_gx_libretro', 'Mega Drive',         'States/Mega Drive'), // Alias for Mega Drive
    'md':        _CoreInfo('genesis_plus_gx_libretro', 'Mega Drive',         'States/Mega Drive'), // Alias for Mega Drive
  };

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
      // EmuDeck mapping returns the folder containing the actual saves
      return p.join(baseDir, coreInfo.saveFolder);
    }

    final exePath = await _directoryService.findEmulatorExecutable('retroarch', 'RetroArch.exe');
    if (exePath == null) return null;

    String exeDir = io.File(exePath).parent.path;
    // If exePath points to a folder instead of an exe, use it directly
    if (await io.FileSystemEntity.isDirectory(exePath)) {
      exeDir = exePath;
    }
    // The saveFolder in _coreMap is relative to the RetroArch installation directory.
    return p.join(exeDir, 'saves', coreInfo.saveFolder);
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
      // states folder is next to saves folder in EmuDeck structure
      statesRoot = p.join(p.dirname(baseDir), 'states', coreInfo.statesFolder);
    } else {
      final exePath = await _directoryService.findEmulatorExecutable('retroarch', 'RetroArch.exe');
      if (exePath == null) return {};
      
      String exeDir = io.File(exePath).parent.path;
      if (await io.FileSystemEntity.isDirectory(exePath)) {
        exeDir = exePath;
      }
      rootSaveDir = p.join(exeDir, 'saves', coreInfo.saveFolder);
      statesRoot = p.join(exeDir, 'states', coreInfo.statesFolder);
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
            if (fname.startsWith(stemLower) && (fname.endsWith('.srm') || fname.endsWith('.sav'))) {
              filesToCheck.add(entity);
              found = true;
              break;
            }
          }
          if (!found) {
            await for (final entity in savesDirObj.list()) {
              if (entity is! io.File) continue;
              final fname = p.basename(entity.path).toLowerCase();
              if (fname.endsWith('.srm') || fname.endsWith('.sav')) {
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
            filesToCheck.add(io.File(p.join(rootSaveDir, '$stem.srm')));
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

      String? targetDir;
      final isState = filename.contains('.state');

      if (io.Platform.isLinux) {
        final baseDir = await _directoryService.getEmulatorAppSupportDirectory('retroarch', platformSlug: slug);
        targetDir = isState
            ? p.join(p.dirname(baseDir), 'states', coreInfo.statesFolder)
            : p.join(baseDir, coreInfo.saveFolder);
      } else {
        final exePath = await _directoryService.findEmulatorExecutable('retroarch', 'RetroArch.exe');
        if (exePath == null) return false;
        
        String exeDir = io.File(exePath).parent.path;
        if (await io.FileSystemEntity.isDirectory(exePath)) {
          exeDir = exePath;
        }
        targetDir = isState
            ? p.join(exeDir, 'states', coreInfo.statesFolder)
            : p.join(exeDir, 'saves', coreInfo.saveFolder);
      }

      final dir = io.Directory(targetDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      // Handle .sav to .srm renaming for RetroArch NDS cores
      String targetFilename = filename;
      if (!isState && filename.toLowerCase().endsWith('.sav')) {
        targetFilename = '${p.basenameWithoutExtension(filename)}.srm';
      }

      final targetPath = p.join(targetDir, targetFilename);
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
