import 'dart:io';
import 'dart:typed_data';
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
    test('returns false when Ares data dir cannot be resolved (Windows)', () async {
      // On Windows, _getAresDataDir requires findEmulatorExecutable to succeed.
      // With no ares installed, it returns null and restoreSave returns false.
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final dirService = DirectoryService(prefs);
      final platform = PlatformInfo('windows');
      final strategy = AresSaveStrategy(dirService, platform: platform);

      final game = _makeGame('Test Game.gba', 'gba');
      final result = await strategy.restoreSave(
        game,
        'Test Game.gba',
        Uint8List.fromList([1, 2, 3]),
        'Test Game.gba.ram',
      );
      expect(result, isFalse,
          reason: 'restoreSave returns false on Windows when Ares not installed');
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

      // The data dir should be <HOME>/.local/share/ares/ — does NOT exist yet
      final dataDir = p.join(homeDir.path, '.local', 'share', 'ares');
      final savesGba = Directory(p.join(dataDir, 'Saves', 'Game Boy Advance'));
      expect(await savesGba.exists(), isFalse,
          reason: 'Saves/Game Boy Advance/ should not exist before restoreSave');

      final result = await strategy.restoreSave(
        game,
        'Test Game.gba',
        Uint8List.fromList([1, 2, 3]),
        'Test Game.gba.ram',
      );

      expect(result, isTrue, reason: 'restoreSave should succeed when Ares is installed');
      expect(await savesGba.exists(), isTrue,
          reason: 'restoreSave should create the Saves/<Platform> subfolder');

      final saveFile = File(p.join(savesGba.path, 'test game.ram'));
      expect(await saveFile.exists(), isTrue);
      final contents = await saveFile.readAsBytes();
      expect(contents, [1, 2, 3]);
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
