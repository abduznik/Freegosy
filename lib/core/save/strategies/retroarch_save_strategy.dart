import 'dart:io';
import 'dart:typed_data';

import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for RetroArch emulator.
///
/// Save files live next to RetroArch.exe in saves/{coreName}/.
/// Core name mapping is derived from the platform slug.
class RetroArchSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  RetroArchSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'retroarch';

  static const Map<String, _CoreInfo> _coreMap = {
    'gba':       _CoreInfo('mgba_libretro',            'mGBA',                'mGBA'),
    'gbc':       _CoreInfo('mgba_libretro',            'mGBA',                'mGBA'),
    'gb':        _CoreInfo('mgba_libretro',            'mGBA',                'mGBA'),
    'snes':      _CoreInfo('snes9x_libretro',          'Snes9X',              'Snes9X'),
    'nes':       _CoreInfo('fceumm_libretro',          'FCEUmm',              'FCEUmm'),
    'n64':       _CoreInfo('mupen64plus_next_libretro', 'Mupen64Plus-Next',   'Mupen64Plus-Next'),
    'nds':       _CoreInfo('desmume2015_libretro',     'DeSmuME 2015',        'DeSmuME 2015'),
    'psx':       _CoreInfo('pcsx_rearmed_libretro',    'PCSX-ReARMed',        'PCSX-ReARMed'),
    'psp':       _CoreInfo('ppsspp_libretro',          'PPSSPP/PSP/SAVEDATA', 'PPSSPP'),
    'dreamcast': _CoreInfo('flycast_libretro',         'Flycast',             'Flycast'),
    'megadrive': _CoreInfo('genesis_plus_gx_libretro', 'Genesis Plus GX',    'Genesis Plus GX'),
    'dc':        _CoreInfo('flycast_libretro', 'Flycast', 'Flycast'),
    'ps1':       _CoreInfo('pcsx_rearmed_libretro', 'PCSX-ReARMed', 'PCSX-ReARMed'),
    'playstation': _CoreInfo('pcsx_rearmed_libretro', 'PCSX-ReARMed', 'PCSX-ReARMed'),
    'md':        _CoreInfo('genesis_plus_gx_libretro', 'Genesis Plus GX', 'Genesis Plus GX'),
    'genesis':   _CoreInfo('genesis_plus_gx_libretro', 'Genesis Plus GX', 'Genesis Plus GX'),
  };

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final slug = game.platformSlug?.toLowerCase() ?? '';
    final coreInfo = _coreMap[slug];
    if (coreInfo == null) return null;

    final exePath = await _directoryService.findEmulatorExecutable('retroarch', 'RetroArch.exe');
    if (exePath == null) return null;

    final exeDir = File(exePath).parent.path;
    return '$exeDir/saves/${coreInfo.saveFolder}';
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final slug = game.platformSlug?.toLowerCase() ?? '';
    final coreInfo = _coreMap[slug];
    if (coreInfo == null) return [];

    final exePath = await _directoryService.findEmulatorExecutable('retroarch', 'RetroArch.exe');
    if (exePath == null) return [];
    final exeDir = File(exePath).parent.path;

    final stem = getRomStem(game);
    final candidates = <File>[];

    if (syncMode == 'saves' || syncMode == 'both') {
      final savesDir = '$exeDir/saves/${coreInfo.saveFolder}';
      candidates.add(File('$savesDir/$stem.srm'));
    }

    if (syncMode == 'states' || syncMode == 'both') {
      final statesDir = '$exeDir/states/${coreInfo.statesFolder}';
      candidates.add(File('$statesDir/$stem.state.auto'));
      for (int i = 0; i <= 9; i++) {
        candidates.add(File('$statesDir/$stem.state$i'));
      }
    }

    final result = <File>[];
    for (final f in candidates) {
      if (!await f.exists()) continue;
      if (sessionStart != null) {
        final stat = await f.stat();
        if (stat.modified.isBefore(sessionStart)) continue;
      }
      result.add(f);
    }
    return result;
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final slug = game.platformSlug?.toLowerCase() ?? '';
      final coreInfo = _coreMap[slug];
      if (coreInfo == null) return false;

      final exePath = await _directoryService.findEmulatorExecutable('retroarch', 'RetroArch.exe');
      if (exePath == null) return false;
      final exeDir = File(exePath).parent.path;

      final isState = filename.contains('.state');
      final targetDir = isState
          ? '$exeDir/states/${coreInfo.statesFolder}'
          : '$exeDir/saves/${coreInfo.saveFolder}';

      final dir = Directory(targetDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final targetPath = '$targetDir/$filename';
      await backupSave(targetPath);
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