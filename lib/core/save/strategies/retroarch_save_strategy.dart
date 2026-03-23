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

  // Maps platform slug → (core dll stem, saves subfolder)
  static const Map<String, _CoreInfo> _coreMap = {
    'gba':       _CoreInfo('mgba_libretro',          'mGBA'),
    'gbc':       _CoreInfo('mgba_libretro',          'mGBA'),
    'gb':        _CoreInfo('mgba_libretro',          'mGBA'),
    'snes':      _CoreInfo('snes9x_libretro',        'Snes9X'),
    'nes':       _CoreInfo('fceumm_libretro',        'FCEUmm'),
    'n64':       _CoreInfo('mupen64plus_next_libretro', 'Mupen64Plus-Next'),
    'nds':       _CoreInfo('desmume2015_libretro',   'DeSmuME 2015'),
    'psx':       _CoreInfo('pcsx_rearmed_libretro',  'PCSX-ReARMed'),
    'psp':       _CoreInfo('ppsspp_libretro',        'PPSSPP/PSP/SAVEDATA'),
    'dreamcast': _CoreInfo('flycast_libretro',       'Flycast'),
    'megadrive': _CoreInfo('genesis_plus_gx_libretro', 'Genesis Plus GX'),
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
  Future<List<File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];

    final dir = Directory(saveDir);
    if (!await dir.exists()) return [];

    final stem = getRomStem(game);
    final candidates = [
      File('$saveDir/$stem.srm'),
      File('$saveDir/$stem.state.auto'),
    ];

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
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) return false;

      final dir = Directory(saveDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final targetPath = '$saveDir/$filename';
      await backupSave(targetPath);
      await File(targetPath).writeAsBytes(data);
      print('[RetroArchSaveStrategy] restored $filename to $targetPath');
      return true;
    } catch (e) {
      print('[RetroArchSaveStrategy] restoreSave error: $e');
      return false;
    }
  }
}

class _CoreInfo {
  final String coreName;
  final String saveFolder;
  const _CoreInfo(this.coreName, this.saveFolder);
}
