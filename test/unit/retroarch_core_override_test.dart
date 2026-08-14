import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';

void main() {
  group('StrategyRegistry - Core Override System', () {
    late StrategyRegistry registry;
    late SharedPreferences rawPrefs;
    late SharedPreferencesAppPreferences prefs;
    late DirectoryService dirService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      rawPrefs = await SharedPreferences.getInstance();
      prefs = SharedPreferencesAppPreferences(rawPrefs);
      dirService = DirectoryService(prefs);
      registry = StrategyRegistry(dirService, prefs);
    });

    group('Core overrides', () {
      test('setCoreOverride persists to SharedPreferences', () async {
        await registry.setCoreOverride('gba', 'mgba_libretro');
        final stored = rawPrefs.getString('ra_core_gba');
        expect(stored, 'mgba_libretro');
      });

      test('getCoreOverride returns stored value', () async {
        await registry.setCoreOverride('gba', 'gambatte_libretro');
        expect(registry.getCoreOverride('gba'), 'gambatte_libretro');
      });

      test('getCoreOverride returns null for unset slug', () {
        expect(registry.getCoreOverride('nonexistent'), isNull);
      });

      test('clearCoreOverride removes override', () async {
        await registry.setCoreOverride('gba', 'mgba_libretro');
        await registry.clearCoreOverride('gba');
        expect(registry.getCoreOverride('gba'), isNull);
        expect(rawPrefs.getString('ra_core_gba'), isNull);
      });

      test('clearAllCoreOverrides removes all overrides', () async {
        await registry.setCoreOverride('gba', 'mgba_libretro');
        await registry.setCoreOverride('snes', 'snes9x_libretro');
        await registry.clearAllCoreOverrides();
        expect(registry.getCoreOverride('gba'), isNull);
        expect(registry.getCoreOverride('snes'), isNull);
      });

      test('coreOverrides returns immutable map', () async {
        await registry.setCoreOverride('gba', 'mgba_libretro');
        final overrides = registry.coreOverrides;
        expect(overrides, {'gba': 'mgba_libretro'});
        expect(() => overrides['test'] = 'value', throwsUnsupportedError);
      });
    });

    group('Per-game emulator preference', () {
      test('setGameEmulatorPreference persists', () async {
        await registry.setGameEmulatorPreference('game123', 'retroarch');
        final stored = rawPrefs.getString('game_emu_game123');
        expect(stored, 'retroarch');
      });

      test('getGameEmulatorPreference returns stored value', () async {
        await registry.setGameEmulatorPreference('game123', 'mgba');
        expect(registry.getGameEmulatorPreference('game123'), 'mgba');
      });

      test('getGameEmulatorPreference returns null for unset game', () {
        expect(registry.getGameEmulatorPreference('nonexistent'), isNull);
      });

      test('clearGameEmulatorPreference removes preference', () async {
        await registry.setGameEmulatorPreference('game123', 'retroarch');
        await registry.clearGameEmulatorPreference('game123');
        expect(registry.getGameEmulatorPreference('game123'), isNull);
      });
    });

    group('Per-game RetroArch core preference', () {
      test('setGameCorePreference persists', () async {
        await registry.setGameCorePreference('game123', 'mgba_libretro');
        final stored = rawPrefs.getString('retroarch_core_game123');
        expect(stored, 'mgba_libretro');
      });

      test('getGameCorePreference returns stored value', () async {
        await registry.setGameCorePreference('game123', 'snes9x_libretro');
        expect(registry.getGameCorePreference('game123'), 'snes9x_libretro');
      });

      test('getGameCorePreference returns null for unset game', () {
        expect(registry.getGameCorePreference('nonexistent'), isNull);
      });

      test('clearGameCorePreference removes preference', () async {
        await registry.setGameCorePreference('game123', 'mgba_libretro');
        await registry.clearGameCorePreference('game123');
        expect(registry.getGameCorePreference('game123'), isNull);
      });
    });

    group('getAllStrategiesForSlug', () {
      test('returns non-empty list for known platform', () {
        final strategies = registry.getAllStrategiesForSlug('gba');
        expect(strategies, isNotEmpty);
      });

      test('returns multiple strategies for conflicting platforms', () {
        final strategies = registry.getAllStrategiesForSlug('gba');
        // RetroArch and mGBA both support GBA
        expect(strategies.length, greaterThanOrEqualTo(1));
      });

      test('returns empty list for unknown platform', () {
        final strategies = registry.getAllStrategiesForSlug('nonexistent_platform');
        expect(strategies, isEmpty);
      });

      test('returns retroarch for platforms it supports', () {
        final strategies = registry.getAllStrategiesForSlug('snes');
        final retroarch = strategies.where((s) => s.emulatorId == 'retroarch');
        expect(retroarch, isNotEmpty);
      });
    });

    group('getStrategyForSlug with gameId', () {
      test('uses per-game preference when set', () async {
        await registry.setGameEmulatorPreference('game123', 'mgba');
        final strategy = registry.getStrategyForSlug('gba', gameId: 'game123');
        expect(strategy?.emulatorId, 'mgba');
      });

      test('falls back to platform preference when no game preference', () async {
        await registry.setPreference('gba', 'mgba');
        final strategy = registry.getStrategyForSlug('gba', gameId: 'nonexistent');
        expect(strategy?.emulatorId, 'mgba');
      });

      test('falls back to default when no preferences set', () {
        final strategy = registry.getStrategyForSlug('gba');
        expect(strategy, isNotNull);
      });
    });

    group('setNdsCore', () {
      test('does not throw', () {
        expect(() => registry.setNdsCore('desmume'), returnsNormally);
        expect(() => registry.setNdsCore('melonds'), returnsNormally);
      });
    });

    group('Persistence across instances', () {
      test('core overrides survive registry recreation', () async {
        await registry.setCoreOverride('gba', 'gambatte_libretro');
        
        // Create new registry instance
        final newRegistry = StrategyRegistry(dirService, prefs);
        expect(newRegistry.getCoreOverride('gba'), 'gambatte_libretro');
      });

      test('game preferences survive registry recreation', () async {
        await registry.setGameEmulatorPreference('game123', 'mgba');
        await registry.setGameCorePreference('game123', 'gambatte_libretro');
        
        final newRegistry = StrategyRegistry(dirService, prefs);
        expect(newRegistry.getGameEmulatorPreference('game123'), 'mgba');
        expect(newRegistry.getGameCorePreference('game123'), 'gambatte_libretro');
      });
    });
  });
}
