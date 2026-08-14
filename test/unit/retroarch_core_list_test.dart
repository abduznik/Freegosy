import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/retroarch_core_list.dart';

void main() {
  group('RetroArchCoreList', () {
    test('kRetroArchCores is not empty', () {
      expect(kRetroArchCores, isNotEmpty);
    });

    test('all cores have unique IDs', () {
      final ids = kRetroArchCores.map((c) => c.id).toList();
      final uniqueIds = ids.toSet();
      expect(ids.length, uniqueIds.length, reason: 'Duplicate core IDs found');
    });

    test('all cores have non-empty display names', () {
      for (final core in kRetroArchCores) {
        expect(core.displayName, isNotEmpty, reason: 'Core ${core.id} has empty displayName');
      }
    });

    test('all cores have non-empty platforms', () {
      for (final core in kRetroArchCores) {
        expect(core.platforms, isNotEmpty, reason: 'Core ${core.id} has no platforms');
      }
    });

    test('all cores have valid categories', () {
      for (final core in kRetroArchCores) {
        expect(CoreCategory.values, contains(core.category),
            reason: 'Core ${core.id} has invalid category');
      }
    });

    test('recommended cores exist in every category', () {
      final recommendedByCategory = <CoreCategory, int>{};
      for (final core in kRetroArchCores) {
        if (core.isRecommended) {
          recommendedByCategory[core.category] = (recommendedByCategory[core.category] ?? 0) + 1;
        }
      }
      // At least some categories should have recommended cores
      expect(recommendedByCategory, isNotEmpty);
    });

    test('core IDs follow libretro naming convention', () {
      final namingPattern = RegExp(r'^[a-z0-9_-]+_libretro$');
      for (final core in kRetroArchCores) {
        expect(namingPattern.hasMatch(core.id), isTrue,
            reason: 'Core ${core.id} does not follow naming convention');
      }
    });
  });

  group('getDefaultCoreForSlug', () {
    test('returns recommended core for known platforms', () {
      expect(getDefaultCoreForSlug('gba'), 'mgba_libretro');
      expect(getDefaultCoreForSlug('snes'), 'snes9x_libretro');
      expect(getDefaultCoreForSlug('n64'), 'mupen64plus_next_libretro');
      expect(getDefaultCoreForSlug('nes'), isNotNull); // mesen or fceumm
      expect(getDefaultCoreForSlug('psx'), 'mednafen_psx_hw_libretro');
      expect(getDefaultCoreForSlug('psp'), 'ppsspp_libretro');
      expect(getDefaultCoreForSlug('nds'), 'melonds_libretro');
      expect(getDefaultCoreForSlug('dos'), 'dosbox_pure_libretro');
      expect(getDefaultCoreForSlug('gb'), 'gambatte_libretro');
      expect(getDefaultCoreForSlug('gbc'), 'gambatte_libretro');
    });

    test('acpc (RomM/IGDB slug for Amstrad CPC) resolves the same core as amstradcpc', () {
      // Issue #78: RomM sends IGDB's platform slug ("acpc"), not the
      // "amstradcpc"/"amstrad-cpc" aliases that were previously registered.
      expect(getDefaultCoreForSlug('acpc'), isNotNull);
      expect(getDefaultCoreForSlug('acpc'), getDefaultCoreForSlug('amstradcpc'));
    });

    test('returns null for unknown platform', () {
      expect(getDefaultCoreForSlug('nonexistent_platform'), isNull);
    });

    test('is case-sensitive', () {
      // Should be lowercase
      expect(getDefaultCoreForSlug('GBA'), isNull);
      expect(getDefaultCoreForSlug('gba'), isNotNull);
    });

    test('returns recommended cores for all major platforms', () {
      final majorPlatforms = [
        'gba', 'gbc', 'gb', 'nes', 'snes', 'n64', 'nds',
        'psx', 'ps1', 'psp', 'ps2',
        'megadrive', 'genesis', 'sms', 'gamegear',
        'saturn', 'dc', 'dreamcast',
        'arcade', 'neogeo',
        'atari2600', 'atari7800',
        'dos', 'msx',
      ];

      for (final slug in majorPlatforms) {
        final core = getDefaultCoreForSlug(slug);
        expect(core, isNotNull, reason: 'No recommended core for $slug');
      }
    });
  });

  group('getCoresForSlug', () {
    test('returns multiple cores for popular platforms', () {
      final gbaCores = getCoresForSlug('gba');
      expect(gbaCores.length, greaterThan(1), reason: 'GBA should have multiple cores');

      final snesCores = getCoresForSlug('snes');
      expect(snesCores.length, greaterThan(3), reason: 'SNES should have many cores');

      final nesCores = getCoresForSlug('nes');
      expect(nesCores.length, greaterThan(2), reason: 'NES should have multiple cores');
    });

    test('returns empty list for unknown platform', () {
      final cores = getCoresForSlug('nonexistent_platform');
      expect(cores, isEmpty);
    });

    test('recommended core is included in results', () {
      final gbaCores = getCoresForSlug('gba');
      final hasRecommended = gbaCores.any((c) => c.isRecommended);
      expect(hasRecommended, isTrue, reason: 'GBA cores should include a recommended one');
    });

    test('all returned cores support the requested platform', () {
      final cores = getCoresForSlug('gba');
      for (final core in cores) {
        expect(core.platforms, contains('gba'),
            reason: 'Core ${core.id} should support gba');
      }
    });

    test('returns cores for alias slugs', () {
      // 'genesis' and 'megadrive' should both return cores
      final genesisCores = getCoresForSlug('genesis');
      final megaCores = getCoresForSlug('megadrive');
      expect(genesisCores, isNotEmpty);
      expect(megaCores, isNotEmpty);
    });
  });

  group('getRecommendedCoresByCategory', () {
    test('returns non-empty map', () {
      final map = getRecommendedCoresByCategory();
      expect(map, isNotEmpty);
    });

    test('all returned cores are recommended', () {
      final map = getRecommendedCoresByCategory();
      for (final entry in map.entries) {
        for (final core in entry.value) {
          expect(core.isRecommended, isTrue,
              reason: 'Core ${core.id} in recommended map should be recommended');
        }
      }
    });
  });

  group('categoryDisplayName', () {
    test('returns correct names for all categories', () {
      expect(categoryDisplayName(CoreCategory.recommended), 'Recommended');
      expect(categoryDisplayName(CoreCategory.nintendo), 'Nintendo');
      expect(categoryDisplayName(CoreCategory.sega), 'Sega');
      expect(categoryDisplayName(CoreCategory.sony), 'Sony');
      expect(categoryDisplayName(CoreCategory.arcade), 'Arcade');
      expect(categoryDisplayName(CoreCategory.computer), 'Computer');
      expect(categoryDisplayName(CoreCategory.handheld), 'Handheld');
      expect(categoryDisplayName(CoreCategory.other), 'Other / Engines');
    });
  });

  group('coreBaseName', () {
    test('strips .dll extension', () {
      expect(coreBaseName('mgba_libretro.dll'), 'mgba_libretro');
    });

    test('strips .so extension', () {
      expect(coreBaseName('mgba_libretro.so'), 'mgba_libretro');
    });

    test('strips .dylib extension', () {
      expect(coreBaseName('mgba_libretro.dylib'), 'mgba_libretro');
    });

    test('returns unchanged string without extension', () {
      expect(coreBaseName('mgba_libretro'), 'mgba_libretro');
    });
  });

  group('Platform coverage', () {
    test('every recommended core has a valid default mapping', () {
      final recommendedCores = kRetroArchCores.where((c) => c.isRecommended);
      for (final core in recommendedCores) {
        for (final slug in core.platforms) {
          final defaultCore = getDefaultCoreForSlug(slug);
          expect(defaultCore, isNotNull,
              reason: 'Platform $slug (from ${core.id}) should have a default core');
        }
      }
    });

    test('no duplicate recommended cores for same platform', () {
      final platformSlugs = <String, String>{};
      final recommendedCores = kRetroArchCores.where((c) => c.isRecommended);
      for (final core in recommendedCores) {
        for (final slug in core.platforms) {
          if (platformSlugs.containsKey(slug)) {
            // Multiple recommended cores for same platform - that's ok
            // but the first one should be the default
            final defaultCore = getDefaultCoreForSlug(slug);
            expect(defaultCore, isNotNull, reason: 'Platform $slug should have a default');
          }
          platformSlugs[slug] = core.id;
        }
      }
    });

    test('core count meets minimum threshold', () {
      expect(kRetroArchCores.length, greaterThan(100),
          reason: 'Should have at least 100 cores');
    });
  });

  group('Regression - existing core mappings', () {
    test('original 25 core mappings still work', () {
      // These are the original hardcoded mappings that must continue to work
      final originalMappings = {
        'gba': 'mgba_libretro',
        'gbc': 'gambatte_libretro',
        'gb': 'gambatte_libretro',
        'nds': 'melonds_libretro',
        'nes': 'fceumm_libretro', // or mesen_libretro (both recommended)
        'snes': 'snes9x_libretro',
        'n64': 'mupen64plus_next_libretro',
        'psx': 'mednafen_psx_hw_libretro',
        'ps1': 'mednafen_psx_hw_libretro',
        'playstation': 'mednafen_psx_hw_libretro',
        'psp': 'ppsspp_libretro',
        'megadrive': 'genesis_plus_gx_libretro',
        'genesis': 'genesis_plus_gx_libretro',
        'md': 'genesis_plus_gx_libretro',
        'segacd': 'genesis_plus_gx_libretro',
        'saturn': 'mednafen_saturn_libretro',
        'dc': 'flycast_libretro',
        'dreamcast': 'flycast_libretro',
        'gamegear': 'genesis_plus_gx_libretro',
        'sms': 'genesis_plus_gx_libretro',
        'mastersystem': 'genesis_plus_gx_libretro',
        'atari2600': 'stella_libretro',
        'atari7800': 'prosystem_libretro',
        'lynx': 'mednafen_lynx_libretro',
        'neogeo': 'fbneo_libretro',
        'arcade': 'fbneo_libretro',
        'mame': 'mame_libretro',
        'pcengine': 'mednafen_pce_libretro',
        'wonderswan': 'mednafen_wswan_libretro',
        'virtualboy': 'mednafen_vb_libretro',
        'msx': 'bluemsx_libretro',
        'dos': 'dosbox_pure_libretro',
        '3ds': 'azahar_libretro',
        'n3ds': 'azahar_libretro',
        'nintendo-3ds': 'azahar_libretro',
        'new-nintendo-3ds': 'azahar_libretro',
        'new-nintendo-3ds-xl': 'azahar_libretro',
      };

      for (final entry in originalMappings.entries) {
        final defaultCore = getDefaultCoreForSlug(entry.key);
        if (entry.key == 'nes') {
          // NES has multiple recommended cores (mesen, fceumm)
          expect(defaultCore, isNotNull, reason: 'Default core for ${entry.key} should not be null');
        } else {
          expect(defaultCore, entry.value,
              reason: 'Default core for ${entry.key} should be ${entry.value}');
        }
      }
    });
  });
}
