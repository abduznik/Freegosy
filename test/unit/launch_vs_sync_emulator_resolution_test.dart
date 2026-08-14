import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';

/// Regression coverage for issue #28/#42: reports of save sync silently
/// resolving a *different* emulator than the one actually used to launch
/// (e.g. GBA launching via RetroArch but sync looking in mGBA standalone's
/// save folder), on a fresh install with no explicit per-platform
/// preference set yet. Both StrategyRegistry.getStrategyForSlug (used to
/// launch) and SaveSyncService.getStrategyForSlug (used to sync, when no
/// emulatorId override is passed) must agree on which emulator's "first
/// supported" fallback wins for every platform slug that has more than one
/// candidate emulator, or sync will look in the wrong folder.
void main() {
  group('Launch vs. sync emulator resolution agreement (issue #28/#42)', () {
    late StrategyRegistry registry;
    late SaveSyncService syncService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final dirService = DirectoryService(prefs);
      registry = StrategyRegistry(dirService, prefs);
      final rommService = RommService(RomMConfig(baseUrl: '', username: '', password: ''));
      syncService = SaveSyncService(rommService, dirService, registry, prefs);
    });

    test('GBA: launch strategy and no-preference sync strategy agree', () {
      final launchStrategy = registry.getStrategyForSlug('gba');
      final syncStrategy = syncService.getStrategyForSlug('gba');
      expect(launchStrategy, isNotNull);
      expect(syncStrategy, isNotNull);
      expect(
        syncStrategy!.strategyId,
        launchStrategy!.emulatorId,
        reason: 'SaveSyncService resolved "${syncStrategy.strategyId}" but the game '
            'would actually launch via "${launchStrategy.emulatorId}" — saves would '
            'be looked up in the wrong emulator\'s folder.',
      );
    });

    test('every conflicting platform slug: launch and no-preference sync strategy agree', () {
      final conflicts = registry.detectConflicts();
      for (final entry in conflicts.entries) {
        final slug = entry.key;
        final launchStrategy = registry.getStrategyForSlug(slug);
        final syncStrategy = syncService.getStrategyForSlug(slug);
        if (launchStrategy == null || syncStrategy == null) continue;
        expect(
          syncStrategy.strategyId,
          launchStrategy.emulatorId,
          reason: 'slug="$slug": sync resolved "${syncStrategy.strategyId}" but launch '
              'resolves "${launchStrategy.emulatorId}"',
        );
      }
    });
  });
}
