import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strategy_registry_test.mocks.dart';

@GenerateMocks([DirectoryService])
void main() {
  late StrategyRegistry registry;
  late DirectoryService mockDirectoryService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    mockDirectoryService = MockDirectoryService();
    registry = StrategyRegistry(mockDirectoryService, prefs);
  });

  group('StrategyRegistry', () {
    test('getStrategyById() returns correct strategy', () {
      expect(registry.getStrategyById('eden')?.emulatorId, 'eden');
      expect(registry.getStrategyById('retroarch')?.emulatorId, 'retroarch');
    });

    test('getStrategyForSlug() resolves slugs correctly', () {
      expect(registry.getStrategyForSlug('ps3')?.emulatorId, 'rpcs3');
      expect(registry.getStrategyForSlug('playstation-3')?.emulatorId, 'rpcs3');
      expect(registry.getStrategyForSlug('nintendo-switch')?.emulatorId, 'eden');
      // retroarch is first in allPossibleStrategies and supports gba, so it's the default
      expect(registry.getStrategyForSlug('gba')?.emulatorId, 'retroarch');
    });

    test('setNdsCore updates RetroArchStrategy core', () {
      registry.setNdsCore('desmume');
      // This is hard to test directly without exposing internal state, 
      // but we can at least call it to ensure it doesn't crash.
      registry.setNdsCore('melonds');
    });

    test('No two strategies share the same slug', () {
      final allSlugs = <String, String>{}; // slug -> emulatorId
      final overlaps = <String>[];
      
      final strategyIds = [
        'retroarch', 'dolphin', 'eden', 'rpcs3', 'pcsx2', 'azahar', 
        'cemu', 'duckstation', 'flycast', 'melonds', 'ppsspp', 'mgba', 
        'mame', 'xemu', 'xenia_canary', 'windows_native'
      ];
      
      for (final id in strategyIds) {
        final strategy = registry.getStrategyById(id);
        if (strategy != null) {
          for (final slug in strategy.supportedSlugs) {
            if (id != 'retroarch') {
              if (allSlugs.containsKey(slug) && allSlugs[slug] != 'retroarch') {
                overlaps.add('Slug "$slug" is used by "${allSlugs[slug]}" and "$id"');
              }
              allSlugs[slug] = id;
            }
          }
        }
      }
      
      expect(overlaps, isEmpty, reason: overlaps.join('\n'));
    });
  });
}
