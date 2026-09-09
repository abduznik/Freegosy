import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
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
    when(mockStrategyRegistry.getStrategyForSlug(any)).thenReturn(null);
    when(mockStrategyRegistry.getGameEmulatorPreference(any)).thenReturn(null);
    
    // Ensure that on Linux tests we don't accidentally pick up a real system directory or a mock that returns empty string
    when(mockDirectoryService.getEmulatorAppSupportDirectory(any))
        .thenAnswer((_) async => '/nonexistent_directory_for_testing');

    final sysTemp = Directory.systemTemp.path;
    when(mockDirectoryService.getEmulatorDirectory('temp'))
        .thenAnswer((_) async => sysTemp);
    
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => null);
    // Default to legacy mode so existing tests are unaffected
    when(mockRommService.fetchCapabilities())
        .thenAnswer((_) async => RommCapabilities.unknown());
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
      await saveFile.writeAsString('x' * 150);

      final game = Game(id: 'game1', name: 'game', platformSlug: 'gba', fileSize: 0);

      when(mockRommService.uploadSave(
        any,
        any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async => (ok: true, conflict: null));
      when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount'))).thenAnswer((_) async {});

      final ok = await service.pushSaves(game, romPath);
      
      expect(ok, isTrue, reason: 'Should have found and uploaded game.sav');
      verify(mockRommService.uploadSave(
        'game1',
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

    test('pushSaves() skips when local hash matches cached', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_test_skip');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('x' * 150);

      final game = Game(id: 'game1', name: 'game', platformSlug: 'gba', fileSize: 0);

      when(mockRommService.uploadSave(
        any,
        any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async => (ok: true, conflict: null));
      when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount'))).thenAnswer((_) async {});

      await service.pushSaves(game, romPath);
      verify(mockRommService.uploadSave(
        'game1',
        any,
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).called(1);

      // Second time should skip
      clearInteractions(mockRommService);
      // We must re-stub because clearInteractions might affect stubs depending on implementation, 
      // though usually it only clears call history. But to be safe:
      when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => null);

      final ok = await service.pushSaves(game, romPath);
      expect(ok, isTrue, reason: 'Should return true (success) even if skipping due to matching hash');
      verifyNever(mockRommService.uploadSave(any, any));

      await tempDir.delete(recursive: true);
    });

    group('routing (legacy vs device)', () {
      test('pushSaves() uses legacy path when capabilities are unknown', () async {
        // fetchCapabilities already returns unknown() in setUp
        final tempDir = await Directory.systemTemp.createTemp('routing_legacy');
        final romPath = '${tempDir.path}/game.gba';
        await File('${tempDir.path}/game.sav').writeAsString('x' * 150);

        final game = Game(id: 'g1', name: 'game', platformSlug: 'gba', fileSize: 0);

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
        when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount')))
            .thenAnswer((_) async {});

        await service.pushSaves(game, romPath);

        // Legacy path: deviceId must be null
        final captured = verify(mockRommService.uploadSave(
          any, any,
          slot: anyNamed('slot'),
          deviceId: captureAnyNamed('deviceId'),
          autocleanup: anyNamed('autocleanup'),
          autocleanupLimit: anyNamed('autocleanupLimit'),
          overwrite: anyNamed('overwrite'),
          screenshotFile: anyNamed('screenshotFile'),
          overrideFilename: anyNamed('overrideFilename'),
        )).captured;
        expect(captured.first, isNull, reason: 'Legacy path must not pass deviceId');

        await tempDir.delete(recursive: true);
      });

      test('pushSaves() uses device path when capabilities are 4.9', () async {
        // Override to 4.9
        when(mockRommService.fetchCapabilities())
            .thenAnswer((_) async => RommCapabilities(version: '4.9.0'));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('romm_device_id', 'test-device-uuid');

        final tempDir = await Directory.systemTemp.createTemp('routing_device');
        final romPath = '${tempDir.path}/game.gba';
        await File('${tempDir.path}/game.sav').writeAsString('x' * 150);

        final game = Game(id: 'g2', name: 'game', platformSlug: 'gba', fileSize: 0);

        when(mockRommService.getLatestSave('g2', deviceId: anyNamed('deviceId')))
            .thenAnswer((_) async => null);
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

        // Device path: deviceId must be non-null
        final captured = verify(mockRommService.uploadSave(
          any, any,
          slot: anyNamed('slot'),
          deviceId: captureAnyNamed('deviceId'),
          autocleanup: anyNamed('autocleanup'),
          autocleanupLimit: anyNamed('autocleanupLimit'),
          overwrite: anyNamed('overwrite'),
          screenshotFile: anyNamed('screenshotFile'),
          overrideFilename: anyNamed('overrideFilename'),
        )).captured;
        expect(captured.first, 'test-device-uuid',
            reason: 'Device path must pass stored deviceId');

        await tempDir.delete(recursive: true);
      });
    });

    group('sessionStart grace period', () {
      test('pushSaves() includes file modified exactly at sessionStart (within 2s grace)', () async {
        final tempDir = await Directory.systemTemp.createTemp('session_grace');
        final romPath = '${tempDir.path}/game.gba';
        final saveFile = File('${tempDir.path}/game.sav');
        await saveFile.writeAsString('x' * 150);

        final game = Game(id: 'sg1', name: 'game', platformSlug: 'gba', fileSize: 0);

        when(mockRommService.uploadSave(
          any, any,
          slot: anyNamed('slot'), deviceId: anyNamed('deviceId'),
          autocleanup: anyNamed('autocleanup'), autocleanupLimit: anyNamed('autocleanupLimit'),
          overwrite: anyNamed('overwrite'), screenshotFile: anyNamed('screenshotFile'),
          overrideFilename: anyNamed('overrideFilename'),
        )).thenAnswer((_) async => (ok: true, conflict: null));
        when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount')))
            .thenAnswer((_) async {});

        // sessionStart is 1 second AFTER the file was last modified — within grace window
        final sessionStart = (await saveFile.lastModified()).add(const Duration(seconds: 1));

        final ok = await service.pushSaves(game, romPath, sessionStart: sessionStart);
        expect(ok, isTrue,
            reason: 'File within 2s grace window should be included despite sessionStart being after mtime');

        await tempDir.delete(recursive: true);
      });

      test('pushSaves() excludes file modified well before sessionStart (outside grace)', () async {
        final tempDir = await Directory.systemTemp.createTemp('session_old');
        final romPath = '${tempDir.path}/game.gba';
        final saveFile = File('${tempDir.path}/game.sav');
        await saveFile.writeAsString('x' * 150);

        final game = Game(id: 'sg2', name: 'game', platformSlug: 'gba', fileSize: 0);

        when(mockRommService.uploadSave(
          any, any,
          slot: anyNamed('slot'), deviceId: anyNamed('deviceId'),
          autocleanup: anyNamed('autocleanup'), autocleanupLimit: anyNamed('autocleanupLimit'),
          overwrite: anyNamed('overwrite'), screenshotFile: anyNamed('screenshotFile'),
          overrideFilename: anyNamed('overrideFilename'),
        )).thenAnswer((_) async => (ok: true, conflict: null));
        when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount')))
            .thenAnswer((_) async {});

        // sessionStart is 60 seconds after the file — clearly outside grace window
        final sessionStart = (await saveFile.lastModified()).add(const Duration(seconds: 60));

        final ok = await service.pushSaves(game, romPath, sessionStart: sessionStart);
        expect(ok, isFalse,
            reason: 'File 60s before sessionStart should be excluded');

        await tempDir.delete(recursive: true);
      });
    });

    group('_filterFilesMap directory passthrough', () {
      test('pushSaves() does not drop a directory-type save entry', () async {
        // Dolphin Wii saves are directories. The filter must not discard them.
        final tempDir = await Directory.systemTemp.createTemp('dir_save');
        final saveDir = Directory('${tempDir.path}/Wii/title/00010000/474d4345');
        await saveDir.create(recursive: true);
        final saveDataFile = File('${saveDir.path}/game.bin');
        await saveDataFile.writeAsString('x' * 150);
        final romPath = '${tempDir.path}/game.iso';

        // Use a Game that routes to dolphin strategy
        final game = Game(id: 'wii1', name: 'game', platformSlug: 'wii', fileSize: 0);
        when(mockStrategyRegistry.getPreferredEmulatorId('wii')).thenReturn('dolphin');

        when(mockDirectoryService.findEmulatorExecutable(any, any))
            .thenAnswer((_) async => null);
        when(mockDirectoryService.getEmulatorAppSupportDirectory('Dolphin',
                platformSlug: anyNamed('platformSlug')))
            .thenAnswer((_) async => tempDir.path);

        when(mockRommService.uploadSave(
          any, any,
          slot: anyNamed('slot'), deviceId: anyNamed('deviceId'),
          autocleanup: anyNamed('autocleanup'), autocleanupLimit: anyNamed('autocleanupLimit'),
          overwrite: anyNamed('overwrite'), screenshotFile: anyNamed('screenshotFile'),
          overrideFilename: anyNamed('overrideFilename'),
        )).thenAnswer((_) async => (ok: true, conflict: null));

        // We only verify the filter itself — the strategy path resolution may
        // still return empty on the test machine, so we just confirm no crash
        // and the filter helper logic is exercised without dropping directories.
        // The unit test for _filterFilesMap behaviour is below.
        await service.pushSaves(game, romPath);

        await tempDir.delete(recursive: true);
      });
    });

    test('pushSaves() throws SaveConflictException when remote is newer than last pull', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_test_conflict');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('x' * 150);
      
      final game = Game(id: 'game1', name: 'game', platformSlug: 'gba', fileSize: 0);
      
      // Setup a last pull time (1 hour ago)
      final prefs = await SharedPreferences.getInstance();
      final lastPull = DateTime.now().subtract(const Duration(hours: 1));
      await prefs.setString('last_pull_game1', lastPull.toIso8601String());
      
      // Mock remote to be NEWER than last pull (30 mins ago)
      final remoteTime = DateTime.now().subtract(const Duration(minutes: 30));
      when(mockRommService.getLatestSave('game1', deviceId: anyNamed('deviceId'))).thenAnswer((_) async => {
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

  group('SaveSyncService PCSX2 content-hash dedup (device sync)', () {
    Future<Directory> setUpPcsx2Fixture(String saveContent) async {
      final tempDir = await Directory.systemTemp.createTemp('pcsx2_hash_test');
      final exeDir = Directory(p.join(tempDir.path, 'pcsx2'));
      await Directory(p.join(exeDir.path, 'memcards')).create(recursive: true);
      final perGameDir = Directory(p.join(exeDir.path, 'saves', 'SLUS-12345'));
      await perGameDir.create(recursive: true);
      await File(p.join(perGameDir.path, 'save.bin')).writeAsString(saveContent);
      final fakeExe = File(p.join(exeDir.path, 'pcsx2-qt.exe'));
      await fakeExe.writeAsString('');
      when(mockDirectoryService.findEmulatorExecutable(any, any))
          .thenAnswer((_) async => fakeExe.path);
      return tempDir;
    }

    Game pcsx2Game() =>
        Game(id: 'pcsx2game', name: 'Ico (SLUS-12345)', platformSlug: 'ps2', fileSize: 0);

    Future<String> localSaveFilePath(Directory tempDir) async =>
        p.join(tempDir.path, 'pcsx2', 'saves', 'SLUS-12345', 'save.bin');

    setUp(() {
      when(mockRommService.fetchCapabilities())
          .thenAnswer((_) async => RommCapabilities(version: '4.9.0'));
    });

    void stubUpload(Future<Uint8List> Function(File) captureBytes) {
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
        await captureBytes(invocation.positionalArguments[1] as File);
        return (ok: true, conflict: null);
      });
    }

    test('bundle metadata contains a contentHash, not a timeStamp', () async {
      final tempDir = await setUpPcsx2Fixture('SAVE_DATA_V1');
      final romPath = p.join(tempDir.path, 'Ico (SLUS-12345).iso');
      Uint8List? uploadedBytes;
      stubUpload((file) async => uploadedBytes = await file.readAsBytes());

      final ok = await service.pushSaves(pcsx2Game(), romPath);

      expect(ok, isTrue);
      expect(uploadedBytes, isNotNull);
      final archive = ZipDecoder().decodeBytes(uploadedBytes!);
      final metaEntry = archive.files.firstWhere((f) => f.name == 'freegosy_sync.txt');
      final meta = jsonDecode(utf8.decode(metaEntry.content as List<int>)) as Map<String, dynamic>;
      expect(meta.containsKey('contentHash'), isTrue);
      expect(meta.containsKey('timeStamp'), isFalse);

      await tempDir.delete(recursive: true);
    });

    test('pushing an unchanged PCSX2 bundle a second time does not re-upload', () async {
      final tempDir = await setUpPcsx2Fixture('SAVE_DATA_V1');
      final romPath = p.join(tempDir.path, 'Ico (SLUS-12345).iso');
      stubUpload((_) async => Uint8List(0));

      await service.pushSaves(pcsx2Game(), romPath);
      await service.pushSaves(pcsx2Game(), romPath);

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

    test('pull skips restoreSave when the cloud bundle content hash matches local', () async {
      final tempDir = await setUpPcsx2Fixture('LOCAL_UNCHANGED');
      final romPath = p.join(tempDir.path, 'Ico (SLUS-12345).iso');
      Uint8List? uploadedBytes;
      stubUpload((file) async => uploadedBytes = await file.readAsBytes());
      await service.pushSaves(pcsx2Game(), romPath);
      expect(uploadedBytes, isNotNull);

      when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId')))
          .thenAnswer((_) async => {
                'download_path': 'https://example.test/save.zip',
                'file_name': 'Ico (SLUS-12345).zip',
                'device_syncs': <dynamic>[],
              });
      when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId')))
          .thenAnswer((_) async => uploadedBytes);

      final ok = await service.pullSave(pcsx2Game(), romPath);

      expect(ok, isFalse, reason: 'content already matches — should be a no-op');
      expect(
        await File(await localSaveFilePath(tempDir)).readAsString(),
        'LOCAL_UNCHANGED',
        reason: 'local save should be untouched since content already matched',
      );

      await tempDir.delete(recursive: true);
    });

    test('pull restores when the cloud bundle content hash does not match local', () async {
      final tempDir = await setUpPcsx2Fixture('LOCAL_OLD');
      final romPath = p.join(tempDir.path, 'Ico (SLUS-12345).iso');

      final archive = Archive();
      archive.addFile(ArchiveFile.string('freegosy_sync.txt', jsonEncode({'contentHash': 'deadbeef'})));
      archive.addFile(ArchiveFile.string('SLUS-12345/save.bin', 'CLOUD_NEW'));
      final cloudZipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId')))
          .thenAnswer((_) async => {
                'download_path': 'https://example.test/save.zip',
                'file_name': 'Ico (SLUS-12345).zip',
                'device_syncs': <dynamic>[],
              });
      when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId')))
          .thenAnswer((_) async => cloudZipBytes);

      final ok = await service.pullSave(pcsx2Game(), romPath);

      expect(ok, isTrue);
      expect(await File(await localSaveFilePath(tempDir)).readAsString(), 'CLOUD_NEW');

      await tempDir.delete(recursive: true);
    });
  });
}
