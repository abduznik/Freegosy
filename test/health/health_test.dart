import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Health Checks', () {
    test('RommService initializes without throwing', () {
      final config = RomMConfig(
        baseUrl: 'https://test.com',
        username: 'user',
        password: 'pwd',
      );
      expect(() => RommService(config), returnsNormally);
    });

    test('DirectoryService initializes without throwing', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(() => DirectoryService(prefs), returnsNormally);
    });

    test('StrategyRegistry registers all strategies and detects conflicts', () async {
      final prefs = await SharedPreferences.getInstance();
      final platform = PlatformInfo.current;
      final ds = DirectoryService(prefs, platform: platform);
      final registry = StrategyRegistry(ds, prefs, platform: platform);
      
      final allSlugs = <String, String>{}; // slug -> emulatorId
      final overlapErrors = <String>[];
      
      final strategies = [
        'retroarch', 'dolphin', 'eden', 'rpcs3', 'pcsx2', 'azahar', 
        'cemu', 'duckstation', 'flycast', 'melonds', 'ppsspp', 'mgba', 
        'mame', 'xemu', 'xenia_canary', 'windows_native'
      ];
      
      for (final id in strategies) {
        final def = registry.getDefinition(id);
        bool expectedSupported = false;
        if (def != null) {
          final supported = List<String>.from(def['supported_platforms'] ?? []);
          if (platform.isWindows && supported.contains('windows')) expectedSupported = true;
          if (platform.isLinux && supported.contains('linux')) expectedSupported = true;
          if (platform.isMacOS && supported.contains('macos')) expectedSupported = true;
        } else {
          expectedSupported = true;
        }

        final strategy = registry.getStrategyById(id);
        if (expectedSupported) {
          expect(strategy, isNotNull, reason: 'Strategy $id should be registered on ${platform.os}');
          if (strategy != null) {
            for (final slug in strategy.supportedSlugs) {
              if (id != 'retroarch') {
                if (allSlugs.containsKey(slug) && allSlugs[slug] != 'retroarch') {
                  overlapErrors.add('Slug "$slug" is claimed by both "${allSlugs[slug]}" and "$id"');
                }
                allSlugs[slug] = id;
              }
            }
          }
        } else {
          expect(strategy, isNull, reason: 'Strategy $id should NOT be registered on ${platform.os}');
        }
      }
      
      expect(overlapErrors, isEmpty, reason: overlapErrors.join('\n'));
    });

    test('SaveSyncService initializes without throwing', () async {
      final prefs = await SharedPreferences.getInstance();
      final ds = DirectoryService(prefs);
      final rs = RommService(RomMConfig(baseUrl: 'https://test.com', username: 'u', password: 'p'));
      final reg = StrategyRegistry(ds, prefs);
      expect(() => SaveSyncService(rs, ds, reg, prefs), returnsNormally);
    });

    test('All Save strategies can be instantiated', () async {
      final prefs = await SharedPreferences.getInstance();
      final ds = DirectoryService(prefs);
      final rs = RommService(RomMConfig(baseUrl: 'https://test.com', username: 'u', password: 'p'));
      final reg = StrategyRegistry(ds, prefs);
      final sss = SaveSyncService(rs, ds, reg, prefs);
      
      expect(sss.getStrategyForSlug('gba'), isNotNull);
      expect(sss.getStrategyForSlug('gc'), isNotNull);
      expect(sss.getStrategyForSlug('switch'), isNotNull);
    });
  });
}
