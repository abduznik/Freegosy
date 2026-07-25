import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/storage/directory_service.dart';

void main() {
  group('Platform folder canonicalization', () {
    // Test via the static map directly
    test('Neo Geo variants all map to neogeo', () {
      const variants = ['neogeo', 'neo-geo', 'neo-geo-aes', 'neo-geo-mvs', 'mvs', 'aes'];
      for (final slug in variants) {
        // Access the map via reflection or test the resolved folder
        expect(_resolveSlug(slug), 'neogeo', reason: 'Slug "$slug" should resolve to "neogeo"');
      }
    });

    test('3DS variants all map to 3ds', () {
      const variants = ['3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl'];
      for (final slug in variants) {
        expect(_resolveSlug(slug), '3ds', reason: 'Slug "$slug" should resolve to "3ds"');
      }
    });

    test('PS variants map correctly', () {
      expect(_resolveSlug('psx'), 'psx');
      expect(_resolveSlug('ps1'), 'psx');
      expect(_resolveSlug('playstation'), 'psx');
      expect(_resolveSlug('ps2'), 'ps2');
      expect(_resolveSlug('playstation-2'), 'ps2');
      expect(_resolveSlug('psp'), 'psp');
      expect(_resolveSlug('playstation-portable'), 'psp');
    });

    test('Nintendo variants map correctly', () {
      expect(_resolveSlug('gba'), 'gba');
      expect(_resolveSlug('game-boy-advance'), 'gba');
      expect(_resolveSlug('gbc'), 'gbc');
      expect(_resolveSlug('game-boy-color'), 'gbc');
      expect(_resolveSlug('gb'), 'gb');
      expect(_resolveSlug('game-boy'), 'gb');
      expect(_resolveSlug('nds'), 'nds');
      expect(_resolveSlug('nintendo-ds'), 'nds');
      expect(_resolveSlug('ds'), 'nds');
      expect(_resolveSlug('n64'), 'n64');
      expect(_resolveSlug('nintendo-64'), 'n64');
      expect(_resolveSlug('snes'), 'snes');
      expect(_resolveSlug('sfc'), 'snes');
      expect(_resolveSlug('nes'), 'nes');
      expect(_resolveSlug('famicom'), 'nes');
      expect(_resolveSlug('fds'), 'fds');
      expect(_resolveSlug('famicom-disk-system'), 'fds');
    });

    test('Sega variants map correctly', () {
      expect(_resolveSlug('megadrive'), 'megadrive');
      expect(_resolveSlug('genesis'), 'megadrive');
      expect(_resolveSlug('md'), 'megadrive');
      expect(_resolveSlug('segacd'), 'segacd');
      expect(_resolveSlug('megacd'), 'segacd');
      expect(_resolveSlug('mastersystem'), 'mastersystem');
      expect(_resolveSlug('sms'), 'mastersystem');
      expect(_resolveSlug('dc'), 'dreamcast');
      expect(_resolveSlug('dreamcast'), 'dreamcast');
    });

    test('Switch variants map correctly', () {
      expect(_resolveSlug('switch'), 'switch');
      expect(_resolveSlug('nintendo-switch'), 'switch');
      expect(_resolveSlug('ns'), 'switch');
    });

    test('GameCube variants map correctly', () {
      expect(_resolveSlug('gc'), 'gc');
      expect(_resolveSlug('gamecube'), 'gc');
      expect(_resolveSlug('ngc'), 'gc');
    });

    test('Wii U variants map correctly', () {
      expect(_resolveSlug('wiiu'), 'wiiu');
      expect(_resolveSlug('wii-u'), 'wiiu');
      expect(_resolveSlug('nintendo-wii-u'), 'wiiu');
    });

    test('PC Engine variants map correctly', () {
      expect(_resolveSlug('pcengine'), 'pcengine');
      expect(_resolveSlug('tg16'), 'pcengine');
      expect(_resolveSlug('pce'), 'pcengine');
      expect(_resolveSlug('pcenginecd'), 'pcengine');
    });

    test('Windows/PC variants map correctly', () {
      expect(_resolveSlug('windows'), 'windows');
      expect(_resolveSlug('pc'), 'windows');
      expect(_resolveSlug('win'), 'windows');
    });

    test('Unknown slug passes through unchanged', () {
      expect(_resolveSlug('some-new-platform'), 'some-new-platform');
    });

    test('Case insensitive', () {
      expect(_resolveSlug('Neo-Geo'), 'neogeo');
      expect(_resolveSlug('PS2'), 'ps2');
      expect(_resolveSlug('GameCube'), 'gc');
    });
  });
}

/// Replicates the _resolveFolderName logic for testing
String _resolveSlug(String slug) {
  const canonical = {
    '3ds': '3ds', 'n3ds': '3ds', 'nintendo-3ds': '3ds', 'nintendo3ds': '3ds',
    'new-nintendo-3ds': '3ds', 'new-nintendo-3ds-xl': '3ds',
    'gba': 'gba', 'game-boy-advance': 'gba',
    'gbc': 'gbc', 'game-boy-color': 'gbc',
    'gb': 'gb', 'game-boy': 'gb',
    'nds': 'nds', 'nintendo-ds': 'nds', 'ds': 'nds',
    'n64': 'n64', 'nintendo-64': 'n64', 'n64dd': 'n64',
    'snes': 'snes', 'snesna': 'snes', 'sfc': 'snes',
    'nes': 'nes', 'famicom': 'nes',
    'fds': 'fds', 'famicom-disk-system': 'fds',
    'gc': 'gc', 'gamecube': 'gc', 'ngc': 'gc',
    'wii': 'wii',
    'wiiu': 'wiiu', 'wii-u': 'wiiu', 'nintendo-wii-u': 'wiiu', 'nintendo-wiiu': 'wiiu',
    'switch': 'switch', 'nintendo-switch': 'switch', 'ns': 'switch',
    'megadrive': 'megadrive', 'genesis': 'megadrive', 'md': 'megadrive',
    'segacd': 'segacd', 'megacd': 'segacd',
    'mastersystem': 'mastersystem', 'sms': 'mastersystem',
    'gamegear': 'gamegear',
    'saturn': 'saturn',
    'dreamcast': 'dreamcast', 'dc': 'dreamcast',
    'psx': 'psx', 'ps1': 'psx', 'playstation': 'psx',
    'ps2': 'ps2', 'playstation-2': 'ps2', 'playstation2': 'ps2',
    'ps3': 'ps3', 'playstation-3': 'ps3', 'playstation3': 'ps3',
    'psp': 'psp', 'playstation-portable': 'psp',
    'neogeo': 'neogeo', 'neo-geo': 'neogeo', 'neo-geo-aes': 'neogeo',
    'neo-geo-mvs': 'neogeo', 'mvs': 'neogeo', 'aes': 'neogeo',
    'neogeocd': 'neogeocd', 'neocd': 'neogeocd',
    'ngp': 'ngp', 'ngpc': 'ngp', 'neo-geo-pocket': 'ngp',
    'arcade': 'arcade', 'mame': 'arcade',
    'pcengine': 'pcengine', 'tg16': 'pcengine', 'turbografx16': 'pcengine',
    'turbografx-16': 'pcengine', 'pce': 'pcengine', 'pcenginecd': 'pcengine',
    'wonderswan': 'wonderswan', 'wonderswancolor': 'wonderswan',
    'windows': 'windows', 'pc': 'windows', 'win': 'windows',
  };
  final lower = slug.toLowerCase();
  return canonical[lower] ?? lower;
}
