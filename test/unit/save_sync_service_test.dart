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

    final sysTemp = Directory.systemTemp.path;
    when(mockDirectoryService.getEmulatorDirectory('temp'))
        .thenAnswer((_) async => sysTemp);
    
    final prefs = await SharedPreferences.getInstance();
    when(mockRommService.getLatestSave(any)).thenAnswer((_) async => null);
    service = SaveSyncService(mockRommService, mockDirectoryService, mockStrategyRegistry, prefs);
  });

  group('SaveSyncService', () {
    test('getStrategyForSlug() checks StrategyRegistry user preferences', () async {
      when(mockStrategyRegistry.getPreferredEmulatorId('gba')).thenReturn('retroarch');
      
      final strategy = service.getStrategyForSlug('gba');
      expect(strategy?.strategyId, 'retroarch');
    });

    test('pushSaves() uploads when local hash differs', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_test');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('new content');

      final game = Game(id: 'game1', name: 'game', platformSlug: 'gba', fileSize: 0);

      when(mockRommService.uploadSave(
        any, 
        any, 
        slot: anyNamed('slot'), 
        screenshotFile: anyNamed('screenshotFile'), 
        overrideFilename: anyNamed('overrideFilename')
      )).thenAnswer((_) async => true);
      when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount'))).thenAnswer((_) async {});

      final ok = await service.pushSaves(game, romPath);
      
      expect(ok, isTrue, reason: 'Should have found and uploaded game.sav');
      verify(mockRommService.uploadSave(
        'game1', 
        any, 
        slot: anyNamed('slot'), 
        screenshotFile: anyNamed('screenshotFile'), 
        overrideFilename: anyNamed('overrideFilename')
      )).called(1);
      
      await tempDir.delete(recursive: true);
    });

    test('pushSaves() skips when local hash matches cached', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_test_skip');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('content');

      final game = Game(id: 'game1', name: 'game', platformSlug: 'gba', fileSize: 0);

      when(mockRommService.uploadSave(
        any, 
        any, 
        slot: anyNamed('slot'), 
        screenshotFile: anyNamed('screenshotFile'), 
        overrideFilename: anyNamed('overrideFilename')
      )).thenAnswer((_) async => true);
      when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount'))).thenAnswer((_) async {});

      await service.pushSaves(game, romPath);
      verify(mockRommService.uploadSave(
        'game1', 
        any, 
        slot: anyNamed('slot'), 
        screenshotFile: anyNamed('screenshotFile'), 
        overrideFilename: anyNamed('overrideFilename')
      )).called(1);

      // Second time should skip
      clearInteractions(mockRommService);
      // We must re-stub because clearInteractions might affect stubs depending on implementation, 
      // though usually it only clears call history. But to be safe:
      when(mockRommService.getLatestSave(any)).thenAnswer((_) async => null);

      final ok = await service.pushSaves(game, romPath);
      expect(ok, isTrue, reason: 'Should return true (success) even if skipping due to matching hash');
      verifyNever(mockRommService.uploadSave(any, any));

      await tempDir.delete(recursive: true);
    });

    test('pushSaves() throws SaveConflictException when remote is newer than last pull', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_test_conflict');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('local change');
      
      final game = Game(id: 'game1', name: 'game', platformSlug: 'gba', fileSize: 0);
      
      // Setup a last pull time (1 hour ago)
      final prefs = await SharedPreferences.getInstance();
      final lastPull = DateTime.now().subtract(const Duration(hours: 1));
      await prefs.setString('last_pull_game1', lastPull.toIso8601String());
      
      // Mock remote to be NEWER than last pull (30 mins ago)
      final remoteTime = DateTime.now().subtract(const Duration(minutes: 30));
      when(mockRommService.getLatestSave('game1')).thenAnswer((_) async => {
        'updated_at': remoteTime.toIso8601String(),
        'screenshot_url': 'http://remote-screenshot.png',
      });
      
      await expectLater(
        service.pushSaves(game, romPath),
        throwsA(isA<SaveConflictException>()),
      );
      
      await tempDir.delete(recursive: true);
    });
  });
}
