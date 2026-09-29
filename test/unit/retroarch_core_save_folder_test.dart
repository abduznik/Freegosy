import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/retroarch_core_list.dart';
import 'package:freegosy/core/emulator/retroarch_core_names.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/retroarch_save_strategy.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;

import 'save_sync_regression_test.mocks.dart';

/// With "Sort Saves into Folders by Core" on, RetroArch keeps a core's saves
/// in a folder named after the core's library_name. A game's save must go
/// to its own core's folder, never to another core's.
///
/// Seen on a real install: PS2 memory cards restored for RetroArch landed in
/// `saves/Mupen64Plus-Next/`, the N64 core's folder, because the PS2 entry
/// named a `PCSX2` folder that doesn't exist and the fallback then picked the
/// most recently modified core folder.
void main() {
  late Directory tempDir;
  late String saveRoot;
  late RetroArchSaveStrategy strategy;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ra_core_folder_');
    saveRoot = p.join(tempDir.path, 'saves');
    final configDir = p.join(tempDir.path, 'RetroArch');
    await Directory(configDir).create(recursive: true);
    await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
      'savefile_directory = "$saveRoot"',
      'sort_savefiles_enable = "true"',
    ].join('\n'));
    await Directory(saveRoot).create(recursive: true);

    final dirService = MockDirectoryService();
    when(dirService.findEmulatorExecutable(argThat(isA<String>()), argThat(isA<String>())))
        .thenAnswer((_) async => null);
    when(dirService.linuxSyncPreset).thenReturn('default');
    strategy = RetroArchSaveStrategy(dirService,
        platform: PlatformInfo('windows', environment: {'APPDATA': tempDir.path, 'USERPROFILE': tempDir.path}));
  });

  tearDown(() => tempDir.delete(recursive: true));

  Game game(String slug, String rom) => Game(id: '1', name: rom, fsName: rom, platformSlug: slug, fileSize: 0);
  String romPath(String rom) => p.join(tempDir.path, 'roms', rom);

  test('coreIdFor: the core as RomM\'s player and Argosy name it', () {
    expect(strategy.coreIdFor(game('gba', 'x.gba')), 'mgba');
    expect(strategy.coreIdFor(game('psx', 'x.cue')), 'mednafen_psx_hw', reason: 'the core Freegosy launches PS1 games with');
    expect(strategy.coreIdFor(game('n64', 'x.z64')), 'mupen64plus_next');
    expect(strategy.coreIdFor(game('nds', 'x.nds')), 'melonds');
    expect(strategy.coreIdFor(game('turbografx-cd', 'x.cue')), 'mednafen_pce');
    expect(strategy.coreIdFor(game('unknown-platform', 'x.bin')), isNull);
    // RomM's slugs for systems Freegosy knows by another name.
    expect(strategy.coreIdFor(game('famicom', 'x.nes')), strategy.coreIdFor(game('nes', 'x.nes')));
    expect(strategy.coreIdFor(game('neo-geo-pocket-color', 'x.ngc')), 'mednafen_ngp');

    strategy.setLaunchCoreOverride('pcsx_rearmed_libretro.dll');
    expect(strategy.coreIdFor(game('psx', 'x.cue')), 'pcsx_rearmed', reason: 'the core the game was launched with');
  });

  test('a first save goes to the core\'s own folder, not the most recently modified one', () async {
    final n64 = Directory(p.join(saveRoot, 'Mupen64Plus-Next'))..createSync();
    File(p.join(n64.path, 'Wipeout 64 (Europe).srm')).writeAsBytesSync([1]);

    // (Seen with PS2 memory cards, which now go onto LRPS2's own cards; any
    // platform whose core folder doesn't exist yet had the same problem.)
    final nes = game('nes', 'Castlevania (USA).nes');
    expect(await strategy.getSaveDir(nes, romPath(nes.fsName!)), p.join(saveRoot, 'Mesen'));

    expect(await strategy.restoreSave(nes, romPath(nes.fsName!), Uint8List.fromList([1, 2, 3]), 'Castlevania (USA).srm'),
        isTrue);
    expect(File(p.join(saveRoot, 'Mesen', 'Castlevania (USA).srm')).existsSync(), isTrue);
    expect(n64.listSync().map((e) => p.basename(e.path)), ['Wipeout 64 (Europe).srm']);
  });

  test('folders are named after each core\'s library_name', () async {
    const expected = {
      'n64': 'Mupen64Plus-Next',
      'nes': 'Mesen',
      'ps2': 'LRPS2',
      'psx': 'Beetle PSX HW',
      'gb': 'Gambatte',
      'pcfx': 'Beetle PC-FX',
      'vectrex': 'vecx',
      'pc98': 'Neko Project II Kai',
      'x68000': 'PX68k',
      'nds': 'melonDS',
      'megadrive': 'Genesis Plus GX',
      'saturn': 'Beetle Saturn',
      'dreamcast': 'Flycast',
      'lynx': 'Beetle Lynx',
      'dos': 'DOSBox-pure',
      'amiga': 'PUAE',
      'tg16': 'Beetle PCE',
      'turbografx-cd': 'Beetle PCE',
      'supergrafx': 'Beetle PCE',
      'sega32': 'PicoDrive',
      'jaguar': 'Virtual Jaguar',
    };
    for (final MapEntry(key: slug, value: folder) in expected.entries) {
      final g = game(slug, 'Some Game.bin');
      expect(await strategy.getSaveDir(g, romPath('Some Game.bin')), p.join(saveRoot, folder), reason: slug);
    }
  });

  test('an existing core folder is used as before', () async {
    Directory(p.join(saveRoot, 'Beetle PSX HW')).createSync();
    Directory(p.join(saveRoot, 'Mupen64Plus-Next')).createSync();
    final g = game('psx', 'Crash Bandicoot (Europe).cue');
    expect(await strategy.getSaveDir(g, romPath(g.fsName!)), p.join(saveRoot, 'Beetle PSX HW'));
  });

  test('a save already in another core\'s folder for this game is still found', () async {
    // The ROM-name scan is unchanged: a game played with a different core
    // keeps its save in that core's folder.
    final rearmed = Directory(p.join(saveRoot, 'PCSX-ReARMed'))..createSync();
    File(p.join(rearmed.path, 'Crash Bandicoot (Europe).srm')).writeAsBytesSync([1]);
    final g = game('psx', 'Crash Bandicoot (Europe).cue');
    expect(await strategy.getSaveDir(g, romPath(g.fsName!)), rearmed.path);
  });

  test('every platform a core runs gets the folder of the core Freegosy launches it with', () async {
    // The save folder used to come from a table of its own, which picked
    // other cores than the launch (PCSX-ReARMed for PS1 while Beetle PSX HW
    // was launched, mGBA for Game Boy while Gambatte was) and left out 117
    // platforms, whose saves then never synced.
    const ownLayout = {'ppsspp_libretro', 'azahar_libretro'};
    final missing = <String>[];
    for (final slug in {for (final c in kRetroArchCores) ...c.platforms}) {
      final core = getDefaultCoreForSlug(slug)!;
      final name = kRetroArchCoreLibraryNames[core];
      if (name == null || ownLayout.contains(core)) continue;
      final dir = await strategy.getSaveDir(game(slug, 'Some Game.bin'), romPath('Some Game.bin'));
      if (dir != p.join(saveRoot, name)) missing.add('$slug: $dir, expected $name');
    }
    expect(missing, isEmpty);
  });

  test('a core chosen for the platform decides the folder', () async {
    strategy.loadCoreOverrides({'psx': 'pcsx_rearmed_libretro'});
    final g = game('psx', 'Spyro (USA).cue');
    expect(await strategy.getSaveDir(g, romPath(g.fsName!)), p.join(saveRoot, 'PCSX-ReARMed'));
    expect(strategy.coreIdFor(g), 'pcsx_rearmed');
  });

  test('RetroArch\'s last-used core only counts for a platform it runs', () async {
    // retroarch.cfg's libretro_path is the last core RetroArch loaded. A GBA
    // core there must not send a PS1 save to saves/mGBA/.
    File(p.join(tempDir.path, 'RetroArch', 'retroarch.cfg')).writeAsStringSync([
      'savefile_directory = "$saveRoot"',
      'sort_savefiles_enable = "true"',
      'libretro_path = "C:/RetroArch/cores/mgba_libretro.dll"',
    ].join('\n'));
    final gba = game('gba', 'Metroid (USA).gba');
    expect(await strategy.getSaveDir(gba, romPath(gba.fsName!)), p.join(saveRoot, 'mGBA'));
    // retroarch.cfg has been read now.
    final psx = game('psx', 'Spyro (USA).cue');
    expect(await strategy.getSaveDir(psx, romPath(psx.fsName!)), p.join(saveRoot, 'Beetle PSX HW'));
    strategy.setLaunchCoreOverride(null);
    expect(strategy.coreIdFor(psx), 'mednafen_psx_hw');
  });
}
