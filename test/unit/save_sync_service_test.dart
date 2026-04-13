import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'save_sync_service_test.mocks.dart';

@GenerateMocks([RommService, DirectoryService, StrategyRegistry])
void main() {
  late SaveSyncService service;
  late MockRommService mockRommService;
  late MockDirectoryService mockDirectoryService;
  late MockStrategyRegistry mockStrategyRegistry;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockRommService = MockRommService();
    mockDirectoryService = MockDirectoryService();
    mockStrategyRegistry = MockStrategyRegistry();
    
    // Default preferred emulator is null to use built-in fallbacks
    when(mockStrategyRegistry.getPreferredEmulatorId(any)).thenReturn(null);
    
    // Ensure that on Linux tests we don't accidentally pick up a real system directory or a mock that returns empty string
    when(mockDirectoryService.getEmulatorAppSupportDirectory(any))
        .thenAnswer((_) async => '/nonexistent_directory_for_testing');
    
    service = SaveSyncService(mockRommService, mockDirectoryService, mockStrategyRegistry);
  });

  group('SaveSyncService', () {
    test('getStrategyForSlug() checks StrategyRegistry user preferences', () async {
      when(mockStrategyRegistry.getPreferredEmulatorId('gba')).thenReturn('retroarch');
      
      final strategy = service.getStrategyForSlug('gba');
      expect(strategy?.strategyId, 'retroarch');
    });

    test('pushSaves() uploads when local hash differs', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_test');
      // Use mgba strategy (default for gba slug in SaveSyncService)
      // It looks for .sav next to ROM
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('new content');

      final game = Game(id: 'game1', name: 'game', platformSlug: 'gba', fileSize: 0);

      when(mockRommService.uploadSave(any, any)).thenAnswer((_) async => true);
      when(mockRommService.pruneOldSaves(any)).thenAnswer((_) async => {});

      final ok = await service.pushSaves(game, romPath);
      
      expect(ok, isTrue, reason: 'Should have found and uploaded game.sav');
      verify(mockRommService.uploadSave('game1', any)).called(1);
      
      await tempDir.delete(recursive: true);
    });

    test('pushSaves() skips when local hash matches cached', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_test_skip');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('content');

      final game = Game(id: 'game1', name: 'game', platformSlug: 'gba', fileSize: 0);

      // Mock upload to be sure it's called first time
      when(mockRommService.uploadSave(any, any)).thenAnswer((_) async => true);
      when(mockRommService.pruneOldSaves(any)).thenAnswer((_) async => {});

      await service.pushSaves(game, romPath);
      verify(mockRommService.uploadSave('game1', any)).called(1);

      // Second time should skip
      clearInteractions(mockRommService);
      final ok = await service.pushSaves(game, romPath);
      expect(ok, isFalse, reason: 'Should have skipped upload due to matching hash');
      verifyNever(mockRommService.uploadSave(any, any));

      await tempDir.delete(recursive: true);
    });
  });
}
