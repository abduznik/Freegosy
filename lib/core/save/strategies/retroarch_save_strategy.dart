import 'dart:io';
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

  RetroArchSaveStrategy(this._directoryService);

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
    final coreInfo = _coreMap[slug];
    if (coreInfo == null) return null;

    final exePath = await _directoryService.findEmulatorExecutable('retroarch', 'RetroArch.exe');
    if (exePath == null) return null;

    String exeDir = File(exePath).parent.path;
    // If exePath points to a folder instead of an exe, use it directly
    if (await FileSystemEntity.isDirectory(exePath)) {
      exeDir = exePath;
    }
    // The saveFolder in _coreMap is relative to the RetroArch installation directory.
    return p.join(exeDir, 'saves', coreInfo.saveFolder);
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final slug = game.platformSlug?.toLowerCase() ?? '';
    final coreInfo = _coreMap[slug];
    if (coreInfo == null) return [];

    final exePath = await _directoryService.findEmulatorExecutable('retroarch', 'RetroArch.exe');
    if (exePath == null) return [];
    
    String exeDir = File(exePath).parent.path;
    // If exePath points to a folder instead of an exe, use it directly
    if (await FileSystemEntity.isDirectory(exePath)) {
      exeDir = exePath;
    }

    final stem = getRomStem(game); // Assuming getRomStem is available and correct for generating base filename

    final List<File> filesToReturn = [];

    // Special case for PSP saves
    if (slug == 'psp' || slug == 'playstation-portable') {
      if (syncMode == 'saves' || syncMode == 'both') {
        final pspPath = '$exeDir\\saves\\PPSSPP\\PSP'.replaceAll('/', '\\');
        final pspDir = Directory(pspPath);
        if (await pspDir.exists()) {
          bool hasFiles = false;
          await for (final _ in pspDir.list(recursive: true)) {
            hasFiles = true;
            break;
          }
          if (hasFiles) {
            filesToReturn.add(File(pspPath));
          }
        }
      }
    } else {
      // Existing logic for non-PSP saves (e.g., SRM files)
      if (syncMode == 'saves' || syncMode == 'both') {
        final savesDir = p.join(exeDir, 'saves', coreInfo.saveFolder);
        final savesDirObj = Directory(savesDir);
        if (await savesDirObj.exists()) {
          final stemLower = stem.toLowerCase();
          bool found = false;
          await for (final entity in savesDirObj.list()) {
            if (entity is! File) continue;
            final fname = p.basename(entity.path).toLowerCase();
            if (fname.startsWith(stemLower) && fname.endsWith('.srm')) {
              filesToReturn.add(entity);
              found = true;
              break;
            }
          }
          if (!found) {
            // Also try scanning for any .srm that fuzzy matches the stem
            await for (final entity in savesDirObj.list()) {
              if (entity is! File) continue;
              final fname = p.basename(entity.path).toLowerCase();
              if (fname.endsWith('.srm')) {
                final stemWords = stemLower
                    .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
                    .split(' ')
                    .where((w) => w.length >= 3)
                    .toList();
                if (stemWords.any((word) => fname.contains(word))) {
                  filesToReturn.add(entity);
                  found = true;
                  break;
                }
              }
            }
          }
          if (!found) {
            filesToReturn.add(File(p.join(savesDir, '$stem.srm')));
          }
        } else {
          filesToReturn.add(File(p.join(savesDir, '$stem.srm')));
        }
      }
    }

    // Handle States (regardless of platform)
    if (syncMode == 'states' || syncMode == 'both') {
      final statesDir = p.join(exeDir, 'states', coreInfo.statesFolder);

      // Derive stem from romPath as fallback
      final romStem = File(romPath).uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '');

      // Check state files for both stems
      for (final checkStem in [stem, romStem]) {
        filesToReturn.add(File('$statesDir/$checkStem.state.auto'));
        for (int i = 0; i <= 9; i++) {
          filesToReturn.add(File('$statesDir/$checkStem.state$i'));
        }
      }
    }

    // Filter out non-existent files and apply sessionStart filter
    final finalResult = <File>[];
    for (final f in filesToReturn) {
      final existsAsFile = await f.exists();
      final existsAsDir = await Directory(f.path).exists();
      if (!existsAsFile && !existsAsDir) continue;
      if (sessionStart != null && existsAsFile) {
        final stat = await f.stat();
        if (stat.modified.isBefore(sessionStart)) continue;
      }
      finalResult.add(f);
    }
    return finalResult;
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final slug = game.platformSlug?.toLowerCase() ?? '';
      final coreInfo = _coreMap[slug];
      if (coreInfo == null) return false;

      final exePath = await _directoryService.findEmulatorExecutable('retroarch', 'RetroArch.exe');
      if (exePath == null) return false;
      
      String exeDir = File(exePath).parent.path;
      // If exePath points to a folder instead of an exe, use it directly
      if (await FileSystemEntity.isDirectory(exePath)) {
        exeDir = exePath;
      }

      final isState = filename.contains('.state');
      final targetDir = isState
          ? p.join(exeDir, 'states', coreInfo.statesFolder)
          : p.join(exeDir, 'saves', coreInfo.saveFolder);

      final dir = Directory(targetDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final targetPath = p.join(targetDir, filename);
      await backupSave(targetPath); // Backup existing file
      await File(targetPath).writeAsBytes(data);
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
