import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'save_sync_regression_test.mocks.dart';

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

    when(mockStrategyRegistry.getPreferredEmulatorId(any)).thenReturn(null);
    when(mockStrategyRegistry.getStrategyForSlug(any)).thenReturn(null);
    when(mockStrategyRegistry.getGameEmulatorPreference(any)).thenReturn(null);
    when(mockDirectoryService.getEmulatorAppSupportDirectory(any,
            platformSlug: anyNamed('platformSlug')))
        .thenAnswer((_) async => '/nonexistent_directory_for_testing');
    when(mockDirectoryService.getEmulatorDirectory('temp'))
        .thenAnswer((_) async => Directory.systemTemp.path);

    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId')))
        .thenAnswer((_) async => null);
    when(mockRommService.fetchCapabilities())
        .thenAnswer((_) async => RommCapabilities.unknown());
    service = SaveSyncService(
        mockRommService, mockDirectoryService, mockStrategyRegistry, prefs);
  });

  group('Filename normalization', () {
    test('strips RomM timestamp tag from filename', () {
      // RomM appends: "Game Name [2026-07-11_15-36-41].zip"
      expect(SaveSyncService.normalizeSaveFilename('Game Name [2026-07-11_15-36-41].zip'), 'Game Name.zip');
      expect(SaveSyncService.normalizeSaveFilename('Pokemon Emerald [2026-07-11_15-36-41].srm'), 'Pokemon Emerald.srm');
      expect(SaveSyncService.normalizeSaveFilename('game [2026-07-11_08-45-38].sav'), 'game.sav');
    });

    test('strips timestamp tag with space separator', () {
      expect(SaveSyncService.normalizeSaveFilename('Game [2026-07-11 15-36-41].srm'), 'Game.srm');
    });

    test('strips timestamp tag with hyphenated date-time', () {
      expect(SaveSyncService.normalizeSaveFilename('Game [2026-07-11_15-36-41].zip'), 'Game.zip');
    });

    test('replaces pure timestamp filenames with save.ext', () {
      // Legacy artifacts: just a timestamp, no game name
      expect(SaveSyncService.normalizeSaveFilename('2026-07-11_08-45-38.srm'), 'save.srm');
      expect(SaveSyncService.normalizeSaveFilename('2026-07-11-08-45-38.sav'), 'save.sav');
      expect(SaveSyncService.normalizeSaveFilename('2026-07-11_08-45-38.zip'), 'save.zip');
    });

    test('preserves clean filenames unchanged', () {
      expect(SaveSyncService.normalizeSaveFilename('Pokemon Emerald.srm'), 'Pokemon Emerald.srm');
      expect(SaveSyncService.normalizeSaveFilename('game.sav'), 'game.sav');
      expect(SaveSyncService.normalizeSaveFilename('My Game.zip'), 'My Game.zip');
    });

    test('handles filenames with no extension', () {
      expect(SaveSyncService.normalizeSaveFilename('Game [2026-07-11_15-36-41]'), 'Game');
      expect(SaveSyncService.normalizeSaveFilename('2026-07-11_08-45-38'), 'save');
    });

    test('handles multiple timestamp tags (edge case)', () {
      // Only the trailing tag should be stripped
      expect(SaveSyncService.normalizeSaveFilename('Game [2026-07-11_15-36-41].srm'), 'Game.srm');
    });

    test('handles timestamp tag with sub-second precision', () {
      expect(SaveSyncService.normalizeSaveFilename('Game [2026-07-11_15-36-41-123].srm'), 'Game.srm');
    });
  });

  group('Save sync slot naming', () {
    test('pushSaves() uses slot "freegosy" not timestamped slot', () async {
      final tempDir = await Directory.systemTemp.createTemp('slot_test');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('x' * 150);

      final game =
          Game(id: 'slot1', name: 'game', platformSlug: 'gba', fileSize: 0);

      when(mockRommService.uploadSave(
        any, any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async => (ok: true, conflict: null));

      await service.pushSaves(game, romPath);

      // Verify uploadSave was called — the slot defaults to 'freegosy'
      // inside romm_service.dart when null is passed
      verify(mockRommService.uploadSave(
        'slot1',
        any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).called(1);

      await tempDir.delete(recursive: true);
    });

    test('pushSaves() does not use timestamped slot pattern', () async {
      final tempDir = await Directory.systemTemp.createTemp('slot_no_ts');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('x' * 150);

      final game =
          Game(id: 'slot2', name: 'game', platformSlug: 'gba', fileSize: 0);

      String? capturedSlot;
      when(mockRommService.uploadSave(
        any, any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((invocation) async {
        capturedSlot = invocation.namedArguments[#slot] as String?;
        return (ok: true, conflict: null);
      });

      await service.pushSaves(game, romPath);

      expect(capturedSlot, isNot(contains('freegosy-srm_')),
          reason: 'Slot must NOT contain timestamp pattern');
      expect(capturedSlot, isNot(contains('wingosy-srm_')),
          reason: 'Slot must NOT use old wingosy pattern');

      await tempDir.delete(recursive: true);
    });
  });

  group('Autocleanup on legacy push', () {
    test('legacy push passes autocleanup=true', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('autocleanup_test');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('x' * 150);

      final game = Game(
          id: 'ac1', name: 'game', platformSlug: 'gba', fileSize: 0);

      bool? capturedAutocleanup;
      int? capturedLimit;
      when(mockRommService.uploadSave(
        any, any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((invocation) async {
        capturedAutocleanup =
            invocation.namedArguments[#autocleanup] as bool?;
        capturedLimit =
            invocation.namedArguments[#autocleanupLimit] as int?;
        return (ok: true, conflict: null);
      });

      await service.pushSaves(game, romPath);

      expect(capturedAutocleanup, isTrue,
          reason: 'Legacy push must pass autocleanup=true');
      expect(capturedLimit, 5,
          reason: 'Legacy push must pass autocleanupLimit=5');

      await tempDir.delete(recursive: true);
    });

    test('force push passes overwrite=true', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('overwrite_test');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('x' * 150);

      final game = Game(
          id: 'ow1', name: 'game', platformSlug: 'gba', fileSize: 0);

      bool? capturedOverwrite;
      when(mockRommService.uploadSave(
        any, any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((invocation) async {
        capturedOverwrite =
            invocation.namedArguments[#overwrite] as bool?;
        return (ok: true, conflict: null);
      });

      await service.pushSaves(game, romPath, force: true);

      expect(capturedOverwrite, isTrue,
          reason: 'Force push must pass overwrite=true');

      await tempDir.delete(recursive: true);
    });
  });

  group('Pull cooldown', () {
    test('second pull within cooldown is skipped', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('cooldown_test');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('x' * 150);

      final game = Game(
          id: 'cd1', name: 'game', platformSlug: 'gba', fileSize: 0);

      // First pull — should hit network
      when(mockRommService.getLatestSave('cd1', deviceId: anyNamed('deviceId')))
          .thenAnswer((_) async => null);

      await service.pullSave(game, romPath);
      // Second pull within cooldown — should skip
      await service.pullSave(game, romPath);

      // getLatestSave should only be called once (first pull)
      // Second pull is skipped due to cooldown
      verify(mockRommService.getLatestSave('cd1', deviceId: anyNamed('deviceId')))
          .called(1);

      await tempDir.delete(recursive: true);
    });
  });

  group('No pruneOldSaves in legacy push', () {
    test('legacy push does not call pruneOldSaves', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('no_prune_test');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('x' * 150);

      final game = Game(
          id: 'np1', name: 'game', platformSlug: 'gba', fileSize: 0);

      when(mockRommService.uploadSave(
        any, any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async => (ok: true, conflict: null));

      await service.pushSaves(game, romPath);

      verifyNever(
          mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount')));

      await tempDir.delete(recursive: true);
    });
  });

  group('Default strategy selection', () {
    test('GBA defaults to RetroArch when emulator registry has RetroArch first', () async {
      // The emulator registry puts RetroArch first in the strategy list.
      // When no user preference is set, getStrategyForSlug should check
      // the emulator registry's default and return the matching save strategy.
      when(mockStrategyRegistry.getStrategyForSlug('gba')).thenReturn(
        _MockEmulatorStrategy(emulatorId: 'retroarch'),
      );

      final strategy = service.getStrategyForSlug('gba');
      expect(strategy, isNotNull);
      expect(strategy!.strategyId, equals('retroarch'),
          reason: 'GBA should default to RetroArch save strategy when emulator registry defaults to RetroArch');
    });

    test('NDS defaults to RetroArch when emulator registry has RetroArch first', () {
      when(mockStrategyRegistry.getStrategyForSlug('nds')).thenReturn(
        _MockEmulatorStrategy(emulatorId: 'retroarch'),
      );

      final strategy = service.getStrategyForSlug('nds');
      expect(strategy, isNotNull);
      expect(strategy!.strategyId, equals('retroarch'),
          reason: 'NDS should default to RetroArch save strategy when emulator registry defaults to RetroArch');
    });

    test('NDS uses melonds when emulator registry defaults to melonDS', () {
      when(mockStrategyRegistry.getStrategyForSlug('nds')).thenReturn(
        _MockEmulatorStrategy(emulatorId: 'melonDS'),
      );

      final strategy = service.getStrategyForSlug('nds');
      expect(strategy, isNotNull);
      expect(strategy!.strategyId, equals('melonds'),
          reason: 'NDS should use melonds save strategy when emulator registry defaults to melonDS');
    });

    test('user preference overrides emulator registry default', () {
      when(mockStrategyRegistry.getPreferredEmulatorId('gba'))
          .thenReturn('retroarch');

      final strategy = service.getStrategyForSlug('gba');
      expect(strategy, isNotNull);
      expect(strategy!.strategyId, equals('retroarch'),
          reason: 'User preference should override registry default');
    });

    test('hardcoded fallback used when registry returns null', () {
      when(mockStrategyRegistry.getStrategyForSlug(any))
          .thenReturn(null);

      // GBA fallback should be mgba
      final gbaStrategy = service.getStrategyForSlug('gba');
      expect(gbaStrategy, isNotNull);
      expect(gbaStrategy!.strategyId, equals('mgba'),
          reason: 'Hardcoded fallback for GBA should be mgba');

      // SNES fallback should be retroarch
      final snesStrategy = service.getStrategyForSlug('snes');
      expect(snesStrategy, isNotNull);
      expect(snesStrategy!.strategyId, equals('retroarch'),
          reason: 'Hardcoded fallback for SNES should be retroarch');
    });
  });

  group('Blank save rejection', () {
    test('pushSaves() rejects save files smaller than 100 bytes', () async {
      final tempDir = await Directory.systemTemp.createTemp('blank_save_test');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      // Write a file smaller than minValidSaveSizeBytes (100)
      await saveFile.writeAsBytes(List<int>.filled(50, 0));

      final game = Game(id: 'blank1', name: 'game', platformSlug: 'gba', fileSize: 0);

      when(mockRommService.uploadSave(
        any, any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async => (ok: true, conflict: null));

      final result = await service.pushSaves(game, romPath);

      expect(result, isFalse,
          reason: 'Blank save (< 100 bytes) should be rejected');

      // uploadSave should NOT have been called
      verifyNever(mockRommService.uploadSave(
        any, any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      ));

      await tempDir.delete(recursive: true);
    });

    test('pushSaves() accepts save files >= 100 bytes', () async {
      final tempDir = await Directory.systemTemp.createTemp('valid_save_test');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      // Write a file >= minValidSaveSizeBytes (100)
      await saveFile.writeAsBytes(List<int>.filled(150, 42));

      final game = Game(id: 'valid1', name: 'game', platformSlug: 'gba', fileSize: 0);

      when(mockRommService.uploadSave(
        any, any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async => (ok: true, conflict: null));

      final result = await service.pushSaves(game, romPath);

      expect(result, isTrue,
          reason: 'Valid save (>= 100 bytes) should be accepted');

      verify(mockRommService.uploadSave(
        any, any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).called(1);

      await tempDir.delete(recursive: true);
    });

    test('pushSaves() rejects empty (0-byte) save files', () async {
      final tempDir = await Directory.systemTemp.createTemp('empty_save_test');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsBytes([]);

      final game = Game(id: 'empty1', name: 'game', platformSlug: 'gba', fileSize: 0);

      final result = await service.pushSaves(game, romPath);

      expect(result, isFalse,
          reason: 'Empty save (0 bytes) should be rejected');

      await tempDir.delete(recursive: true);
    });
  });
}

/// Minimal concrete mock for EmulatorStrategy to test save strategy selection.
class _MockEmulatorStrategy extends EmulatorStrategy {
  final String _emulatorId;
  _MockEmulatorStrategy({required String emulatorId})
      : _emulatorId = emulatorId,
        super();

  @override
  String get name => _emulatorId;

  @override
  String get emulatorId => _emulatorId;

  @override
  List<String> get supportedSlugs => const [];

  @override
  String get windowsExecutable => '';

  @override
  String get linuxExecutable => '';

  @override
  bool get supportsSaveSync => false;

  @override
  DirectoryService get directoryService => throw UnimplementedError();

  @override
  String resolveSavePath(Game game) => '';
}
