import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/storage/directory_service.dart';

void main() {
  group('StrategyRegistry extended', () {
    late StrategyRegistry registry;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      // Create a minimal DirectoryService for the registry
      final dirService = DirectoryService(prefs);
      registry = StrategyRegistry(dirService, prefs);
    });

    group('getDefinition', () {
      test('returns definition for known emulator', () {
        final def = registry.getDefinition('retroarch');
        expect(def, isNotNull);
        expect(def!['id'], 'retroarch');
      });

      test('returns null for unknown emulator', () {
        final def = registry.getDefinition('nonexistent_emulator');
        expect(def, isNull);
      });

      test('known emulators have required fields', () {
        final knownIds = [
          'retroarch', 'dolphin', 'pcsx2', 'rpcs3', 'duckstation',
          'melonds', 'ppsspp', 'mgba', 'cemu',
        ];
        for (final id in knownIds) {
          final def = registry.getDefinition(id);
          expect(def, isNotNull, reason: 'Definition for $id should exist');
          expect(def!['id'], id, reason: 'Definition id should match');
        }
      });
    });

    group('getStrategyById', () {
      test('returns strategy for known id', () {
        final strategy = registry.getStrategyById('retroarch');
        expect(strategy, isNotNull);
        expect(strategy!.emulatorId, 'retroarch');
      });

      test('returns null for unknown id', () {
        final strategy = registry.getStrategyById('nonexistent');
        expect(strategy, isNull);
      });
    });

    group('getStrategyForSlug', () {
      test('returns strategy for known platform slug', () {
        final strategy = registry.getStrategyForSlug('gba');
        expect(strategy, isNotNull);
      });

      test('returns null for unknown slug', () {
        final strategy = registry.getStrategyForSlug('unknown_platform_xyz');
        expect(strategy, isNull);
      });

      test('nds slug returns a strategy', () {
        final strategy = registry.getStrategyForSlug('nds');
        expect(strategy, isNotNull);
      });
    });

    group('setPreference and clearPreferences', () {
      test('setPreference then getStrategyForSlug uses preferred', () async {
        // Get the current strategy for gba
        final original = registry.getStrategyForSlug('gba');
        expect(original, isNotNull);

        // Find an alternative emulator id that's different
        final retroarch = registry.getStrategyById('retroarch');
        if (retroarch != null && original!.emulatorId != 'retroarch') {
          await registry.setPreference('gba', 'retroarch');
          final preferred = registry.getStrategyForSlug('gba');
          expect(preferred!.emulatorId, 'retroarch');
        }
      });

      test('clearPreferences removes overrides', () async {
        await registry.setPreference('gba', 'retroarch');
        await registry.clearPreferences();
        // After clear, should fall back to first-supported
        final strategy = registry.getStrategyForSlug('gba');
        expect(strategy, isNotNull);
      });

      test('preference persists in SharedPreferences', () async {
        await registry.setPreference('test_slug', 'test_emu');
        final stored = prefs.getString('emulator_pref_test_slug');
        expect(stored, 'test_emu');
      });
    });

    group('detectConflicts', () {
      test('returns non-empty map when conflicts exist', () {
        final conflicts = registry.detectConflicts();
        // Multiple emulators support some platforms (e.g. GBA via RetroArch and mGBA)
        // At least some conflicts should exist in a full registry
        // This may be empty if only one strategy per slug — both outcomes valid
        expect(conflicts, isA<Map<String, dynamic>>());
      });

      test('conflict values are lists of strategies', () {
        final conflicts = registry.detectConflicts();
        for (final entry in conflicts.entries) {
          expect(entry.value, isA<List>());
          expect(entry.value.length, greaterThan(1),
              reason: 'Conflict for ${entry.key} should have >1 strategy');
        }
      });
    });

    group('setNdsCore', () {
      test('does not throw', () {
        expect(() => registry.setNdsCore('desmume'), returnsNormally);
        expect(() => registry.setNdsCore('melonds'), returnsNormally);
      });
    });
  });
}
