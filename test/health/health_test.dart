import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'dart:io' as io;

void main() {
  group('Health Checks', () {
    test('RommService initializes without throwing', () {
      final config = RomMConfig(
        baseUrl: 'https://test.com',
        username: 'user',
        password: 'pwd',
      );
      expect(() => RommService(config), returnsNormally);
    });

    test('DirectoryService initializes without throwing', () {
      expect(() => DirectoryService(), returnsNormally);
    });

    test('StrategyRegistry registers all strategies and detects conflicts', () async {
      final ds = DirectoryService();
      final registry = StrategyRegistry(ds);
      
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
          if (io.Platform.isWindows && supported.contains('windows')) expectedSupported = true;
          if (io.Platform.isLinux && supported.contains('linux')) expectedSupported = true;
          if (io.Platform.isMacOS && supported.contains('macos')) expectedSupported = true;
        } else {
          expectedSupported = true;
        }

        final strategy = registry.getStrategyById(id);
        if (expectedSupported) {
          expect(strategy, isNotNull, reason: 'Strategy $id should be registered on ${io.Platform.operatingSystem}');
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
          expect(strategy, isNull, reason: 'Strategy $id should NOT be registered on ${io.Platform.operatingSystem}');
        }
      }
      
      expect(overlapErrors, isEmpty, reason: overlapErrors.join('\n'));
    });

    test('SaveSyncService initializes without throwing', () {
      final ds = DirectoryService();
      final rs = RommService(RomMConfig(baseUrl: 'https://test.com', username: 'u', password: 'p'));
      final reg = StrategyRegistry(ds);
      expect(() => SaveSyncService(rs, ds, reg), returnsNormally);
    });

    test('All Save strategies can be instantiated', () {
      final ds = DirectoryService();
      final rs = RommService(RomMConfig(baseUrl: 'https://test.com', username: 'u', password: 'p'));
      final reg = StrategyRegistry(ds);
      final sss = SaveSyncService(rs, ds, reg);
      
      expect(sss.getStrategyForSlug('gba'), isNotNull);
      expect(sss.getStrategyForSlug('gc'), isNotNull);
      expect(sss.getStrategyForSlug('switch'), isNotNull);
    });
  });
}
