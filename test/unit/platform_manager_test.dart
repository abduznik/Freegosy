import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';

void main() {
  group('StrategyRegistry - Platform Manager', () {
    late StrategyRegistry registry;
    late SharedPreferencesAppPreferences prefs;
    late DirectoryService dirService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      dirService = DirectoryService(prefs);
      registry = StrategyRegistry(dirService, prefs);
    });

    group('detectConflicts with merged slugs', () {
      test('returns mergedSlugs for grouped platforms', () {
        final conflicts = registry.detectConflicts();
        // Find a conflict that has merged slugs
        final hasMerged = conflicts.values.any((v) => v.mergedSlugs.isNotEmpty);
        expect(hasMerged, isTrue, reason: 'Some conflicts should have merged slugs');
      });

      test('Game Boy slugs are grouped under single canonical slug', () {
        final conflicts = registry.detectConflicts();
        // Find the Game Boy conflict
        final gbConflict = conflicts.entries.firstWhere(
          (e) => e.key == 'gba' || e.key == 'gb' || e.key == 'game-boy-advance',
          orElse: () => MapEntry('', const (strategies: [], mergedSlugs: [])),
        );
        expect(gbConflict.key, isNotEmpty, reason: 'Game Boy conflict should exist');
        // The canonical slug should be the shortest without hyphens
        expect(gbConflict.key, 'gba');
        // Merged slugs should include the other variants
        expect(gbConflict.value.mergedSlugs, isNotEmpty);
      });

      test('canonical slug prefers shortest without hyphens', () {
        final conflicts = registry.detectConflicts();
        for (final entry in conflicts.entries) {
          // Canonical slug should not contain hyphens if possible
          expect(entry.key.contains('-'), isFalse,
              reason: 'Canonical slug ${entry.key} should not contain hyphens');
        }
      });

      test('conflict values have correct structure', () {
        final conflicts = registry.detectConflicts();
        for (final entry in conflicts.entries) {
          expect(entry.value.strategies, isA<List>());
          expect(entry.value.strategies.length, greaterThanOrEqualTo(2));
          expect(entry.value.mergedSlugs, isA<List<String>>());
        }
      });
    });

    group('per-game emulator preference', () {
      test('set and get game emulator preference', () async {
        await registry.setGameEmulatorPreference('game123', 'mgba');
        expect(registry.getGameEmulatorPreference('game123'), 'mgba');
      });

      test('clear game emulator preference', () async {
        await registry.setGameEmulatorPreference('game123', 'mgba');
        await registry.clearGameEmulatorPreference('game123');
        expect(registry.getGameEmulatorPreference('game123'), isNull);
      });

      test('per-game preference takes precedence over platform preference', () async {
        await registry.setPreference('gba', 'retroarch');
        await registry.setGameEmulatorPreference('game123', 'mgba');
        final strategy = registry.getStrategyForSlug('gba', gameId: 'game123');
        expect(strategy?.emulatorId, 'mgba');
      });
    });

    group('per-game core preference', () {
      test('set and get game core preference', () async {
        await registry.setGameCorePreference('game123', 'mgba_libretro');
        expect(registry.getGameCorePreference('game123'), 'mgba_libretro');
      });

      test('clear game core preference', () async {
        await registry.setGameCorePreference('game123', 'mgba_libretro');
        await registry.clearGameCorePreference('game123');
        expect(registry.getGameCorePreference('game123'), isNull);
      });
    });

    group('per-platform core override', () {
      test('set and get core override', () async {
        await registry.setCoreOverride('gba', 'gambatte_libretro');
        expect(registry.getCoreOverride('gba'), 'gambatte_libretro');
      });

      test('clear core override', () async {
        await registry.setCoreOverride('gba', 'gambatte_libretro');
        await registry.clearCoreOverride('gba');
        expect(registry.getCoreOverride('gba'), isNull);
      });

      test('clear all core overrides', () async {
        await registry.setCoreOverride('gba', 'gambatte_libretro');
        await registry.setCoreOverride('snes', 'snes9x_libretro');
        await registry.clearAllCoreOverrides();
        expect(registry.getCoreOverride('gba'), isNull);
        expect(registry.getCoreOverride('snes'), isNull);
      });

      test('coreOverrides returns immutable map', () async {
        await registry.setCoreOverride('gba', 'gambatte_libretro');
        final overrides = registry.coreOverrides;
        expect(overrides, isA<Map<String, String>>());
        expect(overrides, containsPair('gba', 'gambatte_libretro'));
      });
    });

    group('getAllStrategiesForSlug', () {
      test('returns multiple strategies for GBA', () {
        final strategies = registry.getAllStrategiesForSlug('gba');
        expect(strategies.length, greaterThanOrEqualTo(2));
      });

      test('returns empty for unknown slug', () {
        final strategies = registry.getAllStrategiesForSlug('nonexistent');
        expect(strategies, isEmpty);
      });
    });

    group('persistence', () {
      test('core overrides survive registry recreation', () async {
        await registry.setCoreOverride('gba', 'gambatte_libretro');
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
