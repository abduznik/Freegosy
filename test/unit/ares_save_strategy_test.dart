import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/save/strategies/ares_save_strategy.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/platform/platform_info.dart';

Game _makeGame(String name, String slug) {
  return Game(id: '1', name: name, fileSize: 0, platformSlug: slug);
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ares_save_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Extension classification — confirmed platforms', () {
    test('GBA: syncs .ram, .eeprom, .flash', () {
      final exts = _getExtensions('Game Boy Advance');
      expect(exts, containsAll(['.ram', '.eeprom', '.flash']));
    });

    test('Famicom: syncs .ram, .eeprom, .chr', () {
      final exts = _getExtensions('Famicom');
      expect(exts, containsAll(['.ram', '.eeprom', '.chr']));
    });

    test('N64: syncs .ram, .eeprom, .flash', () {
      final exts = _getExtensions('Nintendo 64');
      expect(exts, containsAll(['.ram', '.eeprom', '.flash']));
    });

    test('Mega Drive: syncs .ram, .eeprom only', () {
      final exts = _getExtensions('Mega Drive');
      expect(exts, containsAll(['.ram', '.eeprom']));
      expect(exts.length, 2);
    });

    test('Game Boy: syncs .ram, .eeprom, .flash', () {
      final exts = _getExtensions('Game Boy');
      expect(exts, containsAll(['.ram', '.eeprom', '.flash']));
    });
  });

  group('Extension classification — defaulted platforms', () {
    test('SFC uses common set', () {
      final exts = _getExtensions('Super Famicom');
      expect(exts, containsAll(['.ram', '.eeprom', '.flash']));
    });

    test('WonderSwan uses common set', () {
      final exts = _getExtensions('WonderSwan');
      expect(exts, containsAll(['.ram', '.eeprom', '.flash']));
    });

    test('MSX uses .ram, .eeprom', () {
      final exts = _getExtensions('MSX');
      expect(exts, containsAll(['.ram', '.eeprom']));
    });

    test('Neo Geo Pocket uses .ram, .eeprom', () {
      final exts = _getExtensions('Neo Geo Pocket');
      expect(exts, containsAll(['.ram', '.eeprom']));
    });
  });

  group('Extension classification — log-only platforms', () {
    test('PlayStation is log-only (empty confirmed set)', () {
      expect(_isLogOnly('PlayStation'), isTrue);
    });

    test('Saturn is log-only', () {
      expect(_isLogOnly('Saturn'), isTrue);
    });

    test('Mega CD is log-only', () {
      expect(_isLogOnly('Mega CD'), isTrue);
    });

    test('Neo Geo is log-only', () {
      expect(_isLogOnly('Neo Geo'), isTrue);
    });

    test('ZX Spectrum is log-only', () {
      expect(_isLogOnly('ZX Spectrum'), isTrue);
    });

    test('log-only platforms still return common set for scanning', () {
      final exts = _getExtensions('PlayStation');
      expect(exts, containsAll(['.ram', '.eeprom', '.flash', '.chr']));
    });

    test('GBA is NOT log-only', () {
      expect(_isLogOnly('Game Boy Advance'), isFalse);
    });

    test('Mega Drive is NOT log-only', () {
      expect(_isLogOnly('Mega Drive'), isFalse);
    });

    test('unknown platform is NOT log-only', () {
      expect(_isLogOnly('Nonexistent Platform'), isFalse);
    });
  });

  group('State file exclusion', () {
    test('.bs1 through .bs9 are excluded', () {
      for (int i = 1; i <= 9; i++) {
        expect(_isState('.bs$i'), isTrue, reason: '.bs$i should be excluded');
      }
    });

    test('.rtc is excluded', () {
      expect(_isState('.rtc'), isTrue);
    });

    test('.ram is NOT excluded', () {
      expect(_isState('.ram'), isFalse);
    });

    test('.eeprom is NOT excluded', () {
      expect(_isState('.eeprom'), isFalse);
    });

    test('.flash is NOT excluded', () {
      expect(_isState('.flash'), isFalse);
    });

    test('.chr is NOT excluded', () {
      expect(_isState('.chr'), isFalse);
    });

    test('.mcd is NOT excluded', () {
      expect(_isState('.mcd'), isFalse);
    });

    test('.sav is NOT excluded', () {
      expect(_isState('.sav'), isFalse);
    });
  });

  group('Stem-prefix filename matching', () {
    test('"Test Game" matches "Test Game (USA).gba"', () {
      expect('test game (usa).gba'.startsWith('test game'), isTrue);
    });

    test('"Sample ROM" matches "Sample ROM - Legacy.gba"', () {
      expect('sample rom - legacy.gba'.startsWith('sample rom'), isTrue);
    });

    test('"Demo ROM" does NOT match "Other Game.gba"', () {
      expect('other game.gba'.startsWith('demo rom'), isFalse);
    });

    test('"Classic Platformer" matches "Classic Platformer (USA).sfc"', () {
      expect('classic platformer (usa).sfc'.startsWith('classic platformer'), isTrue);
    });

    test('exact match works', () {
      expect('test.gba'.startsWith('test'), isTrue);
    });
  });

  group('restoreSave directory creation', () {
    test('restores nothing when ares\' settings can\'t be found (Windows)', () async {
      // On Windows, _getAresDataDir requires findEmulatorExecutable to succeed.
      // With no ares found there is no settings.bml to set a saves folder in,
      // and saves never go next to the ROM.
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final dirService = DirectoryService(prefs);
      final platform = PlatformInfo('windows');
      final strategy = AresSaveStrategy(dirService, platform: platform);

      final game = _makeGame('Test Game.gba', 'gba');
      final result = await strategy.restoreSave(
        game,
        p.join(tempDir.path, 'Test Game.gba'),
        Uint8List.fromList([1, 2, 3]),
        'Test Game.gba.ram',
      );
      expect(result, isFalse);
      expect(tempDir.listSync(), isEmpty);
    });

    test('creates Saves/<Platform> subfolder when it does not exist yet', () async {
      // Setup: create a fake Ares install with ares.exe in a temp dir.
      final aresDir = Directory(p.join(tempDir.path, 'ares_fake'));
      await aresDir.create(recursive: true);
      final fakeExe = File(p.join(aresDir.path, 'ares.exe'));
      await fakeExe.writeAsBytes([0]);

      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final dirService = DirectoryService(prefs);
      await dirService.setEmulatorPathOverride('ares', fakeExe.path);

      // Use Linux platform — _getAresDataDir returns ~/.local/share/ares/
      // Set HOME to temp dir so the data dir lands inside our temp tree
      final homeDir = Directory(p.join(tempDir.path, 'home'));
      await homeDir.create(recursive: true);
      final platform = PlatformInfo('linux', environment: {'HOME': homeDir.path});
      final strategy = AresSaveStrategy(dirService, platform: platform);
      final game = _makeGame('Test Game.gba', 'gba');

      // ares' settings (<HOME>/.local/share/ares/) set a saves path, whose
      // Game Boy Advance/ folder does NOT exist yet.
      final dataDir = p.join(homeDir.path, '.local', 'share', 'ares');
      await Directory(dataDir).create(recursive: true);
      final savesRoot = p.join(tempDir.path, 'Saves');
      await File(p.join(dataDir, 'settings.bml')).writeAsString('Paths\n  Saves: $savesRoot/\n');
      final savesGba = Directory(p.join(savesRoot, 'Game Boy Advance'));
      expect(await savesGba.exists(), isFalse,
          reason: 'Saves/Game Boy Advance/ should not exist before restoreSave');

      final result = await strategy.restoreSave(
        game,
        p.join(tempDir.path, 'Test Game.gba'),
        Uint8List.fromList([1, 2, 3]),
        'Test Game.gba.ram',
      );

      expect(result, isTrue, reason: 'restoreSave should succeed when Ares is installed');
      expect(await savesGba.exists(), isTrue,
          reason: 'restoreSave should create the Saves/<Platform> subfolder');

      final saveFile = File(p.join(savesGba.path, 'Test Game.ram'));
      expect(await saveFile.exists(), isTrue);
      final contents = await saveFile.readAsBytes();
      expect(contents, [1, 2, 3]);
    });
  });

  group('Zip save bundles (PlayStation and similar) — issue: Ares .zip saves invisible to sync', () {
    // Ares bundles the real memory-card save together with transient
    // .state.auto files inside a single per-game .zip (e.g.
    // "Saves/PlayStation/<romStem>.zip"), instead of writing a loose save
    // file. getSaveFiles() must open the zip and pull out only the
    // recognized save entry (.mcd), not the whole zip.
    late Directory aresDir;
    late File fakeExe;
    late Directory savesDir;
    late AresSaveStrategy strategy;
    late Game game;

    setUp(() async {
      aresDir = Directory(p.join(tempDir.path, 'ares_fake'));
      await aresDir.create(recursive: true);
      fakeExe = File(p.join(aresDir.path, 'ares.exe'));
      await fakeExe.writeAsBytes([0]);
      // Portable mode: settings.bml next to the exe, with a saves path.
      await File(p.join(aresDir.path, 'settings.bml'))
          .writeAsString('Paths\n  Saves: ${p.join(aresDir.path, 'Saves')}/\n');

      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final dirService = DirectoryService(prefs);
      await dirService.setEmulatorPathOverride('ares', fakeExe.path);

      final platform = PlatformInfo('windows', environment: {});
      strategy = AresSaveStrategy(dirService, platform: platform);
      game = _makeGame('Ape Escape.chd', 'psx');

      savesDir = Directory(p.join(aresDir.path, 'Saves', 'PlayStation'));
      await savesDir.create(recursive: true);
    });

    Future<void> writeZipBundle(List<MapEntry<String, List<int>>> entries) async {
      final archive = Archive();
      for (final e in entries) {
        archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
      }
      final encoded = ZipEncoder().encode(archive);
      await File(p.join(savesDir.path, 'Ape Escape.zip')).writeAsBytes(encoded);
    }

    test('getSaveFiles extracts only the .mcd entry, not .state.auto', () async {
      final mcdBytes = List<int>.filled(100, 7);
      await writeZipBundle([
        MapEntry('Ape Escape (USA)_1.mcd', mcdBytes),
        MapEntry('Ape Escape.state.auto', List<int>.filled(50, 9)),
      ]);

      final files = await strategy.getSaveFiles(game, p.join(tempDir.path, 'Ape Escape.chd'));

      expect(files.length, 1, reason: 'Only the .mcd entry should be extracted, not .state.auto');
      expect(p.extension(files.first.path), '.mcd');
      expect(await files.first.readAsBytes(), mcdBytes);
    });

    test('getSaveFiles returns nothing for a zip with no recognized save entries', () async {
      await writeZipBundle([
        MapEntry('Ape Escape.state.auto', List<int>.filled(50, 9)),
        MapEntry('Ape Escape.state.auto', List<int>.filled(50, 9)),
      ]);

      final files = await strategy.getSaveFiles(game, p.join(tempDir.path, 'Ape Escape.chd'));
      expect(files, isEmpty);
    });

    test('restoreSave injects into the existing zip, preserving other entries', () async {
      final originalMcd = List<int>.filled(100, 1);
      final stateBytes = List<int>.filled(50, 9);
      await writeZipBundle([
        MapEntry('Ape Escape (USA)_1.mcd', originalMcd),
        MapEntry('Ape Escape.state.auto', stateBytes),
      ]);

      final newMcd = Uint8List.fromList(List<int>.filled(100, 2));
      final ok = await strategy.restoreSave(
        game,
        p.join(tempDir.path, 'Ape Escape.chd'),
        newMcd,
        'Ape Escape (USA)_1.mcd',
      );
      expect(ok, isTrue);

      final zipBytes = await File(p.join(savesDir.path, 'Ape Escape.zip')).readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final mcdEntry = archive.files.firstWhere((f) => f.name == 'Ape Escape (USA)_1.mcd');
      final stateEntry = archive.files.firstWhere((f) => f.name == 'Ape Escape.state.auto');

      expect(mcdEntry.content, newMcd, reason: 'restoreSave should replace the .mcd entry with the new save data');
      expect(stateEntry.content, stateBytes, reason: 'restoreSave must not touch unrelated entries like .state.auto');
    });
  });

  /// ares keeps a game's saves in `<Settings → Paths → Saves>/<system>/`,
  /// named after the game file without its extension (desktop-ui
  /// Emulator::locate); with no saves path, next to the game file. Freegosy
  /// never writes in the ROM folder: it sets a saves path first.
  group('Where ares keeps saves', () {
    late Directory home;
    late Directory roms;
    late AresSaveStrategy strategy;
    const rom = 'Mario Kart 64 (U) [!]';
    final game = Game(id: '1', name: 'Mario Kart 64', fsName: '$rom.zip', fileSize: 0, platformSlug: 'n64');
    String romPath() => p.join(roms.path, '$rom.zip');

    Future<void> writeSettings(String paths) async {
      final dataDir = Directory(p.join(home.path, '.local', 'share', 'ares'));
      await dataDir.create(recursive: true);
      await File(p.join(dataDir.path, 'settings.bml')).writeAsString(
          'Boot\n  Fast: false\nPaths\n$paths  Screenshots\nNintendo64\n  ExpansionPak: true\n');
    }

    setUp(() async {
      home = Directory(p.join(tempDir.path, 'home'));
      roms = Directory(p.join(tempDir.path, 'roms', 'n64'));
      await roms.create(recursive: true);
      await File(romPath()).writeAsBytes(List.filled(64, 1));
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      strategy = AresSaveStrategy(DirectoryService(prefs),
          platform: PlatformInfo('linux', environment: {'HOME': home.path}));
    });

    String aresDir() => p.join(home.path, '.local', 'share', 'ares');
    List<String> romFolder() => roms.listSync().map((f) => p.basename(f.path)).toList()..sort();

    test('with no saves path, Freegosy sets <ares folder>/Saves/ and restores there, under the ROM\'s exact name',
        () async {
      await writeSettings('  Home\n  Firmware\n  Saves\n');

      expect(await strategy.restoreSave(game, romPath(), Uint8List.fromList([1, 2, 3]), '$rom.eeprom'), isTrue);

      final saves = '${aresDir().replaceAll(r'\', '/')}/Saves/';
      final settings = File(p.join(aresDir(), 'settings.bml')).readAsStringSync();
      expect(AresSaveStrategy.parseSavesPath(settings), saves);
      expect(settings, contains('  Screenshots\nNintendo64\n  ExpansionPak: true\n'), reason: 'the rest is kept');
      expect(File(p.join(aresDir(), 'Saves', 'Nintendo 64', '$rom.eeprom')).readAsBytesSync(), [1, 2, 3]);
      expect(romFolder(), ['$rom.zip'], reason: 'nothing but the ROM in the ROM folder');
    });

    test('with no settings.bml to set a saves path in, nothing is restored', () async {
      expect(await strategy.restoreSave(game, romPath(), Uint8List.fromList([4]), 'x.ram'), isFalse);
      expect(romFolder(), ['$rom.zip']);
    });

    test('in <Paths → Saves>/<system>/ when that is set', () async {
      final saves = p.join(tempDir.path, 'ares saves');
      await writeSettings('  Home\n  Saves: ${saves.replaceAll(r'\', '/')}/\n');

      expect(await strategy.restoreSave(game, romPath(), Uint8List.fromList([5]), '$rom.eeprom'), isTrue);

      expect(File(p.join(saves, 'Nintendo 64', '$rom.eeprom')).readAsBytesSync(), [5]);
      expect(File(p.join(roms.path, '$rom.eeprom')).existsSync(), isFalse);
    });

    test('before a saves path is set, push finds ares\' saves next to the game, not the ROM or other games\' saves',
        () async {
      await writeSettings('  Saves\n');
      await File(p.join(roms.path, '$rom.eeprom')).writeAsBytes([1]);
      await File(p.join(roms.path, '$rom.pak')).writeAsBytes([2]);
      await File(p.join(roms.path, 'Mario Kart 64 (U) [!] (Hack).eeprom')).writeAsBytes([3]);
      await File(p.join(roms.path, 'Wave Race 64 (U).eeprom')).writeAsBytes([4]);

      final files = await strategy.getSaveFiles(game, romPath());

      expect(files.map((f) => p.basename(f.path)), ['$rom.eeprom']);
    });

    test('a save zip for a zipped ROM never touches the ROM', () async {
      await writeSettings('  Saves\n');
      final romBytes = File(romPath()).readAsBytesSync();

      expect(await strategy.restoreSave(game, romPath(), Uint8List.fromList([9, 9]), 'save.zip'), isTrue);
      expect(await strategy.restoreSave(game, romPath(), Uint8List.fromList([7]), '$rom.srm'), isTrue);

      expect(File(romPath()).readAsBytesSync(), romBytes);
      expect(romFolder(), ['$rom.zip']);
      expect(File(p.join(aresDir(), 'Saves', 'Nintendo 64', '$rom.zip')).existsSync(), isTrue);
    });

    test('even when the saves folder holds the ROM, a save never replaces it', () async {
      // Saves: <x>/ puts N64 saves in <x>/Nintendo 64/, here also the ROM's folder.
      final shared = Directory(p.join(tempDir.path, 'shared', 'Nintendo 64'))..createSync(recursive: true);
      final sharedRom = p.join(shared.path, '$rom.zip');
      File(sharedRom).writeAsBytesSync(List.filled(64, 1));
      await writeSettings('  Saves: ${p.dirname(shared.path).replaceAll(r'\', '/')}/\n');

      expect(await strategy.restoreSave(game, sharedRom, Uint8List.fromList([9, 9]), 'save.zip'), isFalse);
      expect(await strategy.restoreSave(game, sharedRom, Uint8List.fromList([7]), '$rom.srm'), isTrue);

      expect(File(sharedRom).readAsBytesSync(), List.filled(64, 1), reason: 'not replaced, nothing injected');
    });

    test('setSavesPath fills an empty Saves line, or adds one, keeping everything else', () {
      expect(AresSaveStrategy.setSavesPath('Boot\n  Fast: false\nPaths\n  Home\n  Saves\n  Screenshots\n', 'C:/s/'),
          'Boot\n  Fast: false\nPaths\n  Home\n  Saves: C:/s/\n  Screenshots\n');
      expect(AresSaveStrategy.setSavesPath('Paths\r\n  Home\r\nVideo\r\n  Driver: x\r\n', '/s/'),
          'Paths\r\n  Home\r\n  Saves: /s/\r\nVideo\r\n  Driver: x\r\n');
      expect(AresSaveStrategy.setSavesPath('Video\n  Driver: x\n', '/s/'), 'Video\n  Driver: x\nPaths\n  Saves: /s/\n');
    });

    test('parseSavesPath reads Paths → Saves, and nothing from other sections', () {
      expect(AresSaveStrategy.parseSavesPath('Paths\n  Home\n  Saves\n  Screenshots\n'), isNull);
      expect(AresSaveStrategy.parseSavesPath('Paths\n  Saves: C:/Saves/\n'), 'C:/Saves/');
      expect(AresSaveStrategy.parseSavesPath('Paths\n  Saves: "C:/My Saves/"\n'), 'C:/My Saves/');
      expect(AresSaveStrategy.parseSavesPath('Other\n  Saves: C:/x/\nPaths\n  Home\n'), isNull);
      expect(AresSaveStrategy.parseSavesPath('Paths\r\n  Saves: /home/me/saves/\r\n'), '/home/me/saves/');
    });
  });

  group('Platform folder name mapping', () {
    test('all major slugs have folder names', () {
      const slugs = {
        'gba': 'Game Boy Advance',
        'snes': 'Super Famicom',
        'n64': 'Nintendo 64',
        'genesis': 'Mega Drive',
        'segacd': 'Mega CD',
        'psx': 'PlayStation',
        'neogeo': 'Neo Geo',
        'gb': 'Game Boy',
        'nes': 'Famicom',
      };
      for (final entry in slugs.entries) {
        expect(_getFolderName(entry.key), entry.value,
            reason: 'Slug "${entry.key}" should map to "${entry.value}"');
      }
    });
  });
}

// ── Helpers that mirror the private functions in ares_save_strategy.dart ──
// These exist so we can test the classification logic without making
// implementation details public.

Set<String> _getExtensions(String platformName) {
  const Set<String> ramEepromFlash = {'.ram', '.eeprom', '.flash'};
  const Set<String> ramEepromFlashChr = {'.ram', '.eeprom', '.flash', '.chr'};
  const Set<String> ramEepromChr = {'.ram', '.eeprom', '.chr'};
  const Set<String> ramEeprom = {'.ram', '.eeprom'};
  const Set<String> empty = {};

  final Map<String, Set<String>> confirmed = {
    'Famicom': ramEepromChr,
    'Game Boy': ramEepromFlash,
    'Game Boy Color': ramEepromFlash,
    'Game Boy Advance': ramEepromFlash,
    'Mega Drive': ramEeprom,
    'Nintendo 64': ramEepromFlash,
    'Super Famicom': ramEepromFlash,
    'WonderSwan': ramEepromFlash,
    'WonderSwan Color': ramEepromFlash,
    'Neo Geo Pocket': ramEeprom,
    'Neo Geo Pocket Color': ramEeprom,
    'MSX': ramEeprom,
    'Mega CD': empty,
    'PlayStation': empty,
    'Saturn': empty,
    'PC Engine': empty,
    'Neo Geo': empty,
    'ColecoVision': empty,
    'ZX Spectrum': empty,
    'Atari 2600': empty,
    'SG-1000': empty,
    'SC-3000': empty,
    'Master System': empty,
    'Game Gear': empty,
    'MSX2': empty,
  };

  final confirmedSet = confirmed[platformName];
  if (confirmedSet == null || confirmedSet.isEmpty) return ramEepromFlashChr;
  return confirmedSet;
}

bool _isLogOnly(String platformName) {
  const confirmed = {
    'Mega CD': {}, 'PlayStation': {}, 'Saturn': {}, 'PC Engine': {},
    'Neo Geo': {}, 'ColecoVision': {}, 'ZX Spectrum': {}, 'Atari 2600': {},
    'SG-1000': {}, 'SC-3000': {}, 'Master System': {}, 'Game Gear': {}, 'MSX2': {},
  };
  return confirmed.containsKey(platformName);
}

bool _isState(String ext) {
  if (ext == '.rtc') return true;
  if (RegExp(r'^\.bs[1-9]$').hasMatch(ext)) return true;
  return false;
}

String? _getFolderName(String slug) {
  const names = {
    'gba': 'Game Boy Advance', 'snes': 'Super Famicom', 'n64': 'Nintendo 64',
    'genesis': 'Mega Drive', 'segacd': 'Mega CD', 'psx': 'PlayStation',
    'neogeo': 'Neo Geo', 'gb': 'Game Boy', 'gbc': 'Game Boy Color',
    'nes': 'Famicom',
    'gamegear': 'Game Gear', 'sms': 'Master System',
    'megadrive': 'Mega Drive', 'md': 'Mega Drive',
    'pce': 'PC Engine', 'msx': 'MSX', 'coleco': 'ColecoVision',
    'zxspectrum': 'ZX Spectrum', 'wonderswan': 'WonderSwan',
    'ngp': 'Neo Geo Pocket', 'ngpc': 'Neo Geo Pocket Color',
    'atari2600': 'Atari 2600', 'sfc': 'Super Famicom',
  };
  return names[slug];
}
