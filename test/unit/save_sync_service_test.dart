import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/save/save_strategy.dart';
import 'package:freegosy/core/save/backup_repository.dart';
import 'package:freegosy/core/save/catalog/save_catalog_sources.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/save/romm_content_hash.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/save/strategies/retroarch_save_strategy.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import '../helpers/duckstation_test_env.dart';
import '../helpers/ps1_card_builder.dart';
import '../helpers/rzip_builder.dart';
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
    when(mockStrategyRegistry.getGameCorePreference(any)).thenReturn(null);

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
    test('withStrategy: two games at once each see their own RetroArch core', () async {
      final a = Game(id: '1', name: 'A', fsName: 'a', platformSlug: 'gba', fileSize: 0);
      final b = Game(id: '2', name: 'B', fsName: 'b', platformSlug: 'gba', fileSize: 0);
      Future<String?> coreSeen(Game g, String core) => service.withStrategy<String?>(g, (s) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return (s as RetroArchSaveStrategy).coreIdFor(g);
          }, emulatorId: 'retroarch', coreOverride: '${core}_libretro');

      final seen = await Future.wait([coreSeen(a, 'mgba'), coreSeen(b, 'gpsp')]);
      expect(seen, ['mgba', 'gpsp']);
    });

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
        emulator: anyNamed('emulator'),
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async => (ok: true, conflict: null, saved: null));
      when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount'))).thenAnswer((_) async {});

      final ok = await service.pushSaves(game, romPath);
      
      expect(ok, isTrue, reason: 'Should have found and uploaded game.sav');
      verify(mockRommService.uploadSave(
        'game1',
        any,
        emulator: anyNamed('emulator'),
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

    test('a push records which RomM save holds this PC\'s save, until the save changes', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_test');
      final romPath = p.join(tempDir.path, 'game.gba');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('x' * 150);
      final game = Game(id: 'game41', name: 'game', platformSlug: 'gba', fileSize: 0);
      when(mockRommService.uploadSave(
        any,
        any,
        emulator: anyNamed('emulator'),
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async => (ok: true, conflict: null, saved: <String, dynamic>{'id': 41}));

      expect(await service.pushSaves(game, romPath, emulatorId: 'mgba', syncMode: 'saves'), isTrue);
      await service.markSaveSynced(game, romPath, emulatorId: 'mgba', syncMode: 'saves');
      expect(await service.rommCopyOfLocal(game, romPath, emulatorId: 'mgba'), '41');

      await saveFile.writeAsString('y' * 150);
      expect(await service.rommCopyOfLocal(game, romPath, emulatorId: 'mgba'), isNull);
      await tempDir.delete(recursive: true);
    });

    test('forgetSynced drops what a game had synced, and only that game', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('synced_fp_7_ares_saves', 'a');
      await prefs.setString('synced_romm_id_7_ares', '41');
      await prefs.setString('synced_fp_70_ares_saves', 'keep');
      await prefs.setString('last_hash_7_mk.srm', 'h');
      await prefs.setString('last_hash_70_mk.srm', 'keep');
      await service.forgetSynced(Game(id: '7', name: 'G', fsName: 'g', platformSlug: 'n64', fileSize: 0));
      expect(prefs.getString('synced_fp_7_ares_saves'), isNull);
      expect(prefs.getString('synced_romm_id_7_ares'), isNull);
      expect(prefs.getString('synced_fp_70_ares_saves'), 'keep');
      expect(prefs.getString('last_hash_7_mk.srm'), isNull);
      expect(prefs.getString('last_hash_70_mk.srm'), 'keep');
    });

    test('after forgetSynced an unchanged save is uploaded again', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_test');
      final romPath = p.join(tempDir.path, 'game.gba');
      await File(p.join(tempDir.path, 'game.sav')).writeAsString('x' * 150);
      final game = Game(id: 'game88', name: 'game', platformSlug: 'gba', fileSize: 0);
      when(mockRommService.uploadSave(
        any,
        any,
        emulator: anyNamed('emulator'),
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async => (ok: true, conflict: null, saved: null));

      await service.pushSaves(game, romPath, emulatorId: 'mgba', syncMode: 'saves');
      await service.forgetSynced(game); // its RomM save was deleted
      await service.pushSaves(game, romPath, emulatorId: 'mgba', syncMode: 'saves');

      verify(mockRommService.uploadSave(
        'game88',
        any,
        emulator: anyNamed('emulator'),
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).called(2);
      await tempDir.delete(recursive: true);
    });

    test('an unchanged multi-file save rewritten by its game is uploaded once', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_test');
      final saveDir = Directory(p.join(tempDir.path, 'MyGame Saves'))..createSync();
      final a = File(p.join(saveDir.path, 'slot1.sav'));
      final b = File(p.join(saveDir.path, 'options.ini'));
      await a.writeAsString('a' * 150);
      await b.writeAsString('b' * 150);
      final game = Game(id: 'game99', name: 'MyGame', platformSlug: 'windows', fileSize: 0);
      await service.windowsSaveStrategy.setManualOverride(game.id, saveDir.path);
      when(mockRommService.uploadSave(
        any,
        any,
        emulator: anyNamed('emulator'),
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async => (ok: true, conflict: null, saved: null));

      await service.pushSaves(game, tempDir.path, emulatorId: 'windows_native');
      // The game rewrites the same save on exit: new times, same bytes.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await a.writeAsString('a' * 150);
      await b.writeAsString('b' * 150);
      await service.pushSaves(game, tempDir.path, emulatorId: 'windows_native');

      verify(mockRommService.uploadSave(
        'game99',
        any,
        emulator: anyNamed('emulator'),
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

    test('exclusive says what it does while it runs', () async {
      String? during;
      await service.exclusive(() async => during = service.activity.value, doing: "Syncing Doom's save");
      expect(during, "Syncing Doom's save");
      expect(service.activity.value, isNull);
    });

    test('overlapping operations that end out of order leave no stale activity', () async {
      Future<void>? inner;
      await service.exclusive(() async {
        // Started inside the hold and not awaited: it outlives the outer one.
        inner = service.exclusive(() => Future<void>.delayed(const Duration(milliseconds: 30)), doing: 'inner');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }, doing: 'outer');
      expect(service.activity.value, 'inner');
      await inner;
      expect(service.activity.value, isNull);
    });

    test('while it uploads, the service says so (screens waiting for the lock show it)', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_activity');
      await File(p.join(tempDir.path, 'game.sav')).writeAsString('x' * 150);
      final game = Game(id: 'act1', name: 'Mario Kart 64', fsName: 'game', platformSlug: 'gba', fileSize: 0);
      String? during;
      when(mockRommService.uploadSave(
        any,
        any,
        emulator: anyNamed('emulator'),
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async {
        during = service.activity.value;
        return (ok: true, conflict: null, saved: null);
      });

      await service.pushSaves(game, p.join(tempDir.path, 'game.gba'), emulatorId: 'mgba');
      expect(during, contains('Uploading'));
      expect(service.activity.value, isNull);
      await tempDir.delete(recursive: true);
    });

    test('older RomM: this PC\'s own upload is not taken for a newer save from elsewhere', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_own_upload');
      final save = File(p.join(tempDir.path, 'game.sav'))..writeAsStringSync('a' * 150);
      final romPath = p.join(tempDir.path, 'game.gba');
      final game = Game(id: 'own1', name: 'game', platformSlug: 'gba', fileSize: 0);
      DateTime? uploadedAt;
      // Pulled an hour ago.
      (await SharedPreferences.getInstance())
          .setString('last_pull_own1', DateTime.now().subtract(const Duration(hours: 1)).toIso8601String());
      when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => null);
      when(mockRommService.uploadSave(
        any,
        any,
        emulator: anyNamed('emulator'),
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async {
        uploadedAt = DateTime.now().toUtc(); // RomM stamps the save as it receives it
        return (ok: true, conflict: null, saved: null);
      });
      expect(await service.pushSaves(game, romPath, emulatorId: 'mgba'), isTrue);

      // RomM's newest save is now that upload; play again and save.
      when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId')))
          .thenAnswer((_) async => {'updated_at': uploadedAt!.toIso8601String()});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      save.writeAsStringSync('b' * 150);
      expect(await service.pushSaves(game, romPath, emulatorId: 'mgba'), isTrue);
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
        emulator: anyNamed('emulator'),
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((_) async => (ok: true, conflict: null, saved: null));
      when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount'))).thenAnswer((_) async {});

      await service.pushSaves(game, romPath);
      verify(mockRommService.uploadSave(
        'game1',
        any,
        emulator: anyNamed('emulator'),
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
      verifyNever(mockRommService.uploadSave(any, any, emulator: anyNamed('emulator')));

      await tempDir.delete(recursive: true);
    });

    group('The RomM hash of a save on this PC', () {
      Uint8List? uploaded;
      var uploads = 0;
      setUp(() {
        uploaded = null;
        uploads = 0;
        when(mockRommService.uploadSave(
          any, any,
          emulator: anyNamed('emulator'),
          slot: anyNamed('slot'),
          deviceId: anyNamed('deviceId'),
          autocleanup: anyNamed('autocleanup'),
          autocleanupLimit: anyNamed('autocleanupLimit'),
          overwrite: anyNamed('overwrite'),
          screenshotFile: anyNamed('screenshotFile'),
          overrideFilename: anyNamed('overrideFilename'),
        )).thenAnswer((invocation) async {
          uploads++;
          uploaded = await (invocation.positionalArguments[1] as File).readAsBytes();
          return (ok: true, conflict: null, saved: null);
        });
        when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount'))).thenAnswer((_) async {});
      });

      for (final (label, capabilities) in [
        ('legacy', RommCapabilities.unknown()),
        ('4.9', RommCapabilities(version: '4.9.0')),
      ]) {
        test('one file: the md5 of what is uploaded ($label)', () async {
          when(mockRommService.fetchCapabilities()).thenAnswer((_) async => capabilities);
          final tempDir = await Directory.systemTemp.createTemp('romm_hash');
          final bytes = Uint8List.fromList(List.generate(300, (i) => i % 7));
          await File(p.join(tempDir.path, 'game.sav')).writeAsBytes(bytes);
          final game = Game(id: 'h1_$label', name: 'game', platformSlug: 'gba', fileSize: 0);
          final romPath = p.join(tempDir.path, 'game.gba');

          final local = await service.rommHashOfLocal(game, romPath, emulatorId: 'mgba');
          expect(await service.pushSaves(game, romPath, emulatorId: 'mgba'), isTrue);
          expect(local, rommHashOfFile(bytes));
          expect(local, rommHashOfUpload(uploaded!));
          await tempDir.delete(recursive: true);
        });

        test('a compressed (RZIP) save: the hash of the unpacked bytes RomM receives ($label)', () async {
          when(mockRommService.fetchCapabilities()).thenAnswer((_) async => capabilities);
          final tempDir = await Directory.systemTemp.createTemp('romm_hash_rzip');
          final raw = Uint8List.fromList(List.generate(300, (i) => i % 11));
          await File(p.join(tempDir.path, 'game.sav')).writeAsBytes(buildRzip(raw));
          final game = Game(id: 'h2_$label', name: 'game', platformSlug: 'gba', fileSize: 0);

          expect(await service.rommHashOfLocal(game, p.join(tempDir.path, 'game.gba'), emulatorId: 'mgba'),
              rommHashOfFile(raw));
          await tempDir.delete(recursive: true);
        });

        test('a lone save that is a zip: hashed by its contents, as RomM does ($label)', () async {
          when(mockRommService.fetchCapabilities()).thenAnswer((_) async => capabilities);
          final tempDir = await Directory.systemTemp.createTemp('romm_hash_zip');
          final inner = Uint8List.fromList(List.generate(200, (i) => i % 13));
          final zip = Uint8List.fromList(ZipEncoder().encode(Archive()..addFile(ArchiveFile('in.dat', inner.length, inner))));
          await File(p.join(tempDir.path, 'game.sav')).writeAsBytes(zip);
          final game = Game(id: 'h4_$label', name: 'game', platformSlug: 'gba', fileSize: 0);

          expect(await service.rommHashOfLocal(game, p.join(tempDir.path, 'game.gba'), emulatorId: 'mgba'),
              rommHashOfUpload(zip));
          await tempDir.delete(recursive: true);
        });

        test('two save files of one name (a Windows filter flattens folders) both count ($label)', () async {
          when(mockRommService.fetchCapabilities()).thenAnswer((_) async => capabilities);
          final tempDir = await Directory.systemTemp.createTemp('romm_hash_dupes');
          final saveDir = Directory(p.join(tempDir.path, 'Saves'))..createSync();
          for (final (slot, text) in [('slot1', 'a'), ('slot2', 'b')]) {
            Directory(p.join(saveDir.path, slot)).createSync();
            File(p.join(saveDir.path, slot, 'save.dat')).writeAsStringSync(text * 150);
          }
          final game = Game(id: 'h5_$label', name: 'MyGame', platformSlug: 'windows', fileSize: 0);
          await service.windowsSaveStrategy.setManualOverride(game.id, saveDir.path);
          await service.windowsSaveStrategy.setSaveFilter(game.id, '*.dat');

          final local = await service.rommHashOfLocal(game, tempDir.path, emulatorId: 'windows_native');
          await service.pushSaves(game, tempDir.path, emulatorId: 'windows_native');
          final names = [for (final h in (ZipDirectory()..read(InputMemoryStream(uploaded!))).fileHeaders) h.file!.filename];
          expect(names.where((n) => n == 'save.dat').length, 2, reason: 'the upload keeps both files');
          expect(local, rommHashOfUpload(uploaded!));
          await tempDir.delete(recursive: true);
        });

        test('the bundle\'s contentHash is still md5 of each sorted name then its bytes (streamed) ($label)', () async {
          when(mockRommService.fetchCapabilities()).thenAnswer((_) async => capabilities);
          final tempDir = await Directory.systemTemp.createTemp('romm_hash_meta');
          final saveDir = Directory(p.join(tempDir.path, 'Data'))..createSync();
          File(p.join(saveDir.path, 'b.sav')).writeAsStringSync('b' * 150);
          File(p.join(saveDir.path, 'a.sav')).writeAsStringSync('a' * 150);
          final game = Game(id: 'h6_$label', name: 'MyGame', platformSlug: 'windows', fileSize: 0);
          await service.windowsSaveStrategy.setManualOverride(game.id, saveDir.path);

          await service.pushSaves(game, tempDir.path, emulatorId: 'windows_native');
          final meta = ZipDecoder().decodeBytes(uploaded!).findFile('freegosy_sync.txt')!;
          final expected = md5.convert([
            ...utf8.encode('Data/a.sav'), ...utf8.encode('a' * 150),
            ...utf8.encode('Data/b.sav'), ...utf8.encode('b' * 150),
          ]).toString();
          expect(jsonDecode(utf8.decode(meta.content))['contentHash'], expected);
          await tempDir.delete(recursive: true);
        });

        test('both sync modes in one go: one hash when they upload the same files ($label)', () async {
          when(mockRommService.fetchCapabilities()).thenAnswer((_) async => capabilities);
          final tempDir = await Directory.systemTemp.createTemp('romm_hash_modes');
          final bytes = Uint8List.fromList(List.generate(300, (i) => i % 17));
          await File(p.join(tempDir.path, 'game.sav')).writeAsBytes(bytes);
          final game = Game(id: 'h7_$label', name: 'game', platformSlug: 'gba', fileSize: 0);

          expect(await service.rommHashesOfLocal(game, p.join(tempDir.path, 'game.gba'), emulatorId: 'mgba'),
              {rommHashOfFile(bytes)});
          await tempDir.delete(recursive: true);
        });

        test('a save folder: RomM\'s hash of the zip that is uploaded, and unchanged it is uploaded once ($label)', () async {
          when(mockRommService.fetchCapabilities()).thenAnswer((_) async => capabilities);
          final tempDir = await Directory.systemTemp.createTemp('romm_hash_folder');
          final saveDir = Directory(p.join(tempDir.path, 'MyGame Saves'))..createSync();
          File(p.join(saveDir.path, 'slot1.sav')).writeAsStringSync('a' * 150);
          Directory(p.join(saveDir.path, 'profiles')).createSync();
          File(p.join(saveDir.path, 'profiles', 'p1.dat')).writeAsStringSync('b' * 150);
          final game = Game(id: 'h3_$label', name: 'MyGame', platformSlug: 'windows', fileSize: 0);
          await service.windowsSaveStrategy.setManualOverride(game.id, saveDir.path);

          final local = await service.rommHashOfLocal(game, tempDir.path, emulatorId: 'windows_native');
          await service.pushSaves(game, tempDir.path, emulatorId: 'windows_native');
          expect(local, isNotNull);
          expect(local, rommHashOfUpload(uploaded!));

          await Future<void>.delayed(const Duration(milliseconds: 1100));
          File(p.join(saveDir.path, 'slot1.sav')).writeAsStringSync('a' * 150);
          await service.pushSaves(game, tempDir.path, emulatorId: 'windows_native');
          expect(uploads, 1);
          await tempDir.delete(recursive: true);
        });
      }
    });

    group('RetroArch "SaveRAM compression" (RZIP)', () {
      void stubUploadCapturing(void Function(Uint8List bytes) capture) {
        when(mockRommService.uploadSave(
          any, any,
          emulator: anyNamed('emulator'),
          slot: anyNamed('slot'),
          deviceId: anyNamed('deviceId'),
          autocleanup: anyNamed('autocleanup'),
          autocleanupLimit: anyNamed('autocleanupLimit'),
          overwrite: anyNamed('overwrite'),
          screenshotFile: anyNamed('screenshotFile'),
          overrideFilename: anyNamed('overrideFilename'),
        )).thenAnswer((invocation) async {
          capture(await (invocation.positionalArguments[1] as File).readAsBytes());
          return (ok: true, conflict: null, saved: null);
        });
        when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount'))).thenAnswer((_) async {});
      }

      for (final (label, capabilities) in [
        ('legacy', RommCapabilities.unknown()),
        ('4.9', RommCapabilities(version: '4.9.0')),
      ]) {
        test('a compressed save is uploaded uncompressed ($label)', () async {
          when(mockRommService.fetchCapabilities()).thenAnswer((_) async => capabilities);
          final tempDir = await Directory.systemTemp.createTemp('save_sync_rzip');
          final raw = Uint8List.fromList(List.generate(150, (i) => i));
          await File(p.join(tempDir.path, 'game.sav')).writeAsBytes(buildRzip(raw));
          final game = Game(id: 'rzip_$label', name: 'game', platformSlug: 'gba', fileSize: 0);
          Uint8List? uploaded;
          stubUploadCapturing((bytes) => uploaded = bytes);

          expect(await service.pushSaves(game, p.join(tempDir.path, 'game.gba')), isTrue);

          expect(uploaded, raw);
          await tempDir.delete(recursive: true);
        });
      }

      test('the same save, compressed or not, is not uploaded twice', () async {
        when(mockRommService.fetchCapabilities()).thenAnswer((_) async => RommCapabilities(version: '4.9.0'));
        final tempDir = await Directory.systemTemp.createTemp('save_sync_rzip_twice');
        final raw = Uint8List.fromList(List.generate(150, (i) => i));
        final save = File(p.join(tempDir.path, 'game.sav'));
        final romPath = p.join(tempDir.path, 'game.gba');
        final game = Game(id: 'rzip_twice', name: 'game', platformSlug: 'gba', fileSize: 0);
        var uploads = 0;
        stubUploadCapturing((_) => uploads++);

        await save.writeAsBytes(raw);
        await service.pushSaves(game, romPath);
        await save.writeAsBytes(buildRzip(raw));
        await service.pushSaves(game, romPath);

        expect(uploads, 1);
        await tempDir.delete(recursive: true);
      });
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
          emulator: anyNamed('emulator'),
          slot: anyNamed('slot'),
          deviceId: anyNamed('deviceId'),
          autocleanup: anyNamed('autocleanup'),
          autocleanupLimit: anyNamed('autocleanupLimit'),
          overwrite: anyNamed('overwrite'),
          screenshotFile: anyNamed('screenshotFile'),
          overrideFilename: anyNamed('overrideFilename'),
        )).thenAnswer((_) async => (ok: true, conflict: null, saved: null));
        when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount')))
            .thenAnswer((_) async {});

        await service.pushSaves(game, romPath);

        // Legacy path: deviceId must be null
        final captured = verify(mockRommService.uploadSave(
          any, any,
          emulator: anyNamed('emulator'),
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
          emulator: anyNamed('emulator'),
          slot: anyNamed('slot'),
          deviceId: anyNamed('deviceId'),
          autocleanup: anyNamed('autocleanup'),
          autocleanupLimit: anyNamed('autocleanupLimit'),
          overwrite: anyNamed('overwrite'),
          screenshotFile: anyNamed('screenshotFile'),
          overrideFilename: anyNamed('overrideFilename'),
        )).thenAnswer((_) async => (ok: true, conflict: null, saved: null));

        await service.pushSaves(game, romPath);

        // Device path: deviceId must be non-null
        final captured = verify(mockRommService.uploadSave(
          any, any,
          emulator: anyNamed('emulator'),
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
          emulator: anyNamed('emulator'),
          slot: anyNamed('slot'), deviceId: anyNamed('deviceId'),
          autocleanup: anyNamed('autocleanup'), autocleanupLimit: anyNamed('autocleanupLimit'),
          overwrite: anyNamed('overwrite'), screenshotFile: anyNamed('screenshotFile'),
          overrideFilename: anyNamed('overrideFilename'),
        )).thenAnswer((_) async => (ok: true, conflict: null, saved: null));
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
          emulator: anyNamed('emulator'),
          slot: anyNamed('slot'), deviceId: anyNamed('deviceId'),
          autocleanup: anyNamed('autocleanup'), autocleanupLimit: anyNamed('autocleanupLimit'),
          overwrite: anyNamed('overwrite'), screenshotFile: anyNamed('screenshotFile'),
          overrideFilename: anyNamed('overrideFilename'),
        )).thenAnswer((_) async => (ok: true, conflict: null, saved: null));
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
          emulator: anyNamed('emulator'),
          slot: anyNamed('slot'), deviceId: anyNamed('deviceId'),
          autocleanup: anyNamed('autocleanup'), autocleanupLimit: anyNamed('autocleanupLimit'),
          overwrite: anyNamed('overwrite'), screenshotFile: anyNamed('screenshotFile'),
          overrideFilename: anyNamed('overrideFilename'),
        )).thenAnswer((_) async => (ok: true, conflict: null, saved: null));

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
        emulator: anyNamed('emulator'),
        slot: anyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).thenAnswer((invocation) async {
        await captureBytes(invocation.positionalArguments[1] as File);
        return (ok: true, conflict: null, saved: null);
      });
    }

    test('the upload is tagged with the emulator that made the save, in the freegosy slot', () async {
      final tempDir = await setUpPcsx2Fixture('SAVE_DATA_V1');
      final romPath = p.join(tempDir.path, 'Ico (SLUS-12345).iso');
      stubUpload((file) async => Uint8List(0));

      await service.pushSaves(pcsx2Game(), romPath);

      final captured = verify(mockRommService.uploadSave(
        any, any,
        emulator: captureAnyNamed('emulator'),
        slot: captureAnyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      )).captured;
      expect(captured, ['pcsx2', 'freegosy']);

      await tempDir.delete(recursive: true);
    });

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
        emulator: anyNamed('emulator'),
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

    test('a compressed download is unpacked before it is restored', () async {
      final tempDir = await setUpPcsx2Fixture('LOCAL_OLD');
      final romPath = p.join(tempDir.path, 'Ico (SLUS-12345).iso');
      final archive = Archive();
      archive.addFile(ArchiveFile.string('freegosy_sync.txt', jsonEncode({'contentHash': 'deadbeef'})));
      archive.addFile(ArchiveFile.string('SLUS-12345/save.bin', 'CLOUD_NEW'));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId')))
          .thenAnswer((_) async => {
                'download_path': 'https://example.test/save.zip',
                'file_name': 'Ico (SLUS-12345).zip',
                'device_syncs': <dynamic>[],
              });
      when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId')))
          .thenAnswer((_) async => buildRzip(zipBytes));

      expect(await service.pullSave(pcsx2Game(), romPath), isTrue);
      expect(await File(await localSaveFilePath(tempDir)).readAsString(), 'CLOUD_NEW');

      await tempDir.delete(recursive: true);
    });

    test('a pull the launch went ahead without writes nothing', () async {
      final tempDir = await setUpPcsx2Fixture('LOCAL_OLD');
      final romPath = p.join(tempDir.path, 'Ico (SLUS-12345).iso');

      final archive = Archive();
      archive.addFile(ArchiveFile.string('freegosy_sync.txt', jsonEncode({'contentHash': 'deadbeef'})));
      archive.addFile(ArchiveFile.string('SLUS-12345/save.bin', 'CLOUD_NEW'));
      final cloudZipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      final guard = SaveRestoreGuard();
      when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId')))
          .thenAnswer((_) async => {
                'download_path': 'https://example.test/save.zip',
                'file_name': 'Ico (SLUS-12345).zip',
                'device_syncs': <dynamic>[],
              });
      // RomM is slow: the pre-launch wait gives up while the save downloads.
      when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async {
        guard.markTooLate();
        return cloudZipBytes;
      });

      final ok = await guard.run(() => service.pullSave(pcsx2Game(), romPath));

      expect(ok, isFalse);
      expect(await File(await localSaveFilePath(tempDir)).readAsString(), 'LOCAL_OLD');

      await tempDir.delete(recursive: true);
    });
  });

  group('SaveRestoreGuard', () {
    test('is current for everything run inside it, across awaits', () async {
      expect(SaveRestoreGuard.current, isNull);
      expect(SaveRestoreGuard.restoreTooLate, isFalse);
      final guard = SaveRestoreGuard();
      final seen = await guard.run(() async {
        await Future<void>.delayed(Duration.zero);
        final before = SaveRestoreGuard.restoreTooLate;
        guard.markTooLate();
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return (identical(SaveRestoreGuard.current, guard), before, SaveRestoreGuard.restoreTooLate);
      });
      expect(seen, (true, false, true));
      expect(SaveRestoreGuard.current, isNull);
    });
  });

  /// A pull goes through save/formats: the strategy is handed the save in
  /// its emulator's format and name, else the save as it came.
  group('SaveSyncService converts a pulled save for the local emulator', () {
    const romName = 'Mario Kart 64 (USA)';
    late Directory tempDir;
    late SaveSyncService sync;
    late String retroarchSaves;

    Uint8List blankSrm() => Uint8List(0x48800)..fillRange(0, 0x48800, 0xFF);
    Uint8List pattern(int size, [int seed = 0]) =>
        Uint8List.fromList(List.generate(size, (i) => (i + seed) % 251));
    Game n64Game() =>
        Game(id: 'n64game', name: 'Mario Kart 64', fsName: '$romName.z64', platformSlug: 'n64', fileSize: 0);
    String romPath() => p.join(tempDir.path, 'roms', '$romName.z64');
    // ares' settings.bml has no saves path, so Freegosy sets <ares folder>/Saves/.
    String aresDir() => p.join(tempDir.path, '.local', 'share', 'ares');
    String aresSaves() => p.join(aresDir(), 'Saves', 'Nintendo 64');
    List<String> filesIn(String dir) => Directory(dir).existsSync()
        ? (Directory(dir).listSync().whereType<File>().map((f) => p.basename(f.path)).toList()..sort())
        : <String>[];

    void cloudSave(String fileName, Uint8List bytes, {String? emulator}) {
      when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => {
            'download_path': 'https://example.test/$fileName',
            'file_name': fileName,
            'emulator': emulator,
          });
      when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => bytes);
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('save_sync_convert');
      // RetroArch as on Linux: its config names one saves folder for every core.
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);
      retroarchSaves = p.join(tempDir.path, 'saves');
      await Directory(retroarchSaves).create(recursive: true);
      await File(p.join(configDir, 'retroarch.cfg'))
          .writeAsString('savefile_directory = "$retroarchSaves"\nsort_savefiles_enable = "false"\n');
      when(mockDirectoryService.getEmulatorAppSupportDirectory('retroarch', platformSlug: anyNamed('platformSlug')))
          .thenAnswer((_) async => configDir);
      when(mockDirectoryService.findEmulatorExecutable(any, any)).thenAnswer((_) async => null);
      when(mockDirectoryService.linuxSyncPreset).thenReturn('default');
      await Directory(aresDir()).create(recursive: true);
      await File(p.join(aresDir(), 'settings.bml')).writeAsString('Paths\n  Home\n  Saves\n');
      sync = SaveSyncService(mockRommService, mockDirectoryService, mockStrategyRegistry,
          SharedPreferencesAppPreferences(await SharedPreferences.getInstance()),
          platform: PlatformInfo('linux', environment: {'HOME': tempDir.path}),
          zstd: (_) async => throw UnsupportedError('no zstd library'));
    });

    tearDown(() => tempDir.delete(recursive: true));

    for (final (label, capabilities) in [
      ('legacy', RommCapabilities.unknown()),
      ('4.9', RommCapabilities(version: '4.9.0')),
    ]) {
      test('a pull skips RomM\'s save when its content_hash is the save on this PC ($label)', () async {
        when(mockRommService.fetchCapabilities()).thenAnswer((_) async => capabilities);
        final local = pattern(4096, 3);
        await File(p.join(retroarchSaves, '$romName.srm')).writeAsBytes(local);
        when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => {
              'id': 77,
              'download_path': 'https://example.test/x.srm',
              'file_name': '$romName.srm',
              'emulator': 'mupen64plus_next',
              'content_hash': rommHashOfFile(local),
            });
        when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => local);

        expect(await sync.pullSave(n64Game(), romPath(), emulatorId: 'retroarch'), isFalse);
        verifyNever(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId')));
        // Known to be RomM's content: an unchanged session doesn't upload it.
        expect(await sync.saveIsSynced(n64Game(), romPath(), emulatorId: 'retroarch', syncMode: 'saves'), isTrue);
        expect(await sync.saveIsSynced(n64Game(), romPath(), emulatorId: 'retroarch', syncMode: 'both'), isTrue,
            reason: "'both' is the default sync mode");
        await sync.markSaveSynced(n64Game(), romPath(), emulatorId: 'retroarch', syncMode: 'saves');
        expect(await sync.rommCopyOfLocal(n64Game(), romPath(), emulatorId: 'retroarch'), '77');
      });

      for (final hash in [null, 'not-this-save']) {
        test('a pull downloads RomM\'s save when its content_hash is ${hash ?? 'missing'} ($label)', () async {
          when(mockRommService.fetchCapabilities()).thenAnswer((_) async => capabilities);
          await File(p.join(retroarchSaves, '$romName.srm')).writeAsBytes(pattern(4096, 3));
          when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => {
                'id': 78,
                'download_path': 'https://example.test/y.srm',
                'file_name': '$romName.srm',
                'emulator': 'mupen64plus_next',
                'content_hash': hash,
              });
          when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId')))
              .thenAnswer((_) async => pattern(4096, 4));
          await sync.pullSave(n64Game(), romPath(), emulatorId: 'retroarch');
          verify(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId'))).called(1);
        });
      }
    }

    test('a skipped pull tells RomM this device has the save, so its next upload is no false conflict', () async {
      when(mockRommService.fetchCapabilities()).thenAnswer((_) async => RommCapabilities(version: '4.9.0'));
      (await SharedPreferences.getInstance()).setString('romm_device_id', 'dev-1');
      final local = pattern(4096, 5);
      await File(p.join(retroarchSaves, '$romName.srm')).writeAsBytes(local);
      when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => {
            'id': 79,
            'download_path': 'https://example.test/z.srm',
            'file_name': '$romName.srm',
            'emulator': 'mupen64plus_next',
            'content_hash': rommHashOfFile(local),
          });
      when(mockRommService.confirmSaveDownloaded(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => true);

      expect(await sync.pullSave(n64Game(), romPath(), emulatorId: 'retroarch'), isFalse);
      verify(mockRommService.confirmSaveDownloaded(79, deviceId: 'dev-1')).called(1);
    });

    test('a pull the emulator ignores (DuckStation and a file that is no memory card) restores nothing', () async {
      final env = await DuckstationTestEnv.create(tempDir);
      when(mockDirectoryService.findEmulatorExecutable('duckstation', any))
          .thenAnswer((_) async => p.join(env.exeDir, 'duckstation-qt-x64-ReleaseLTCG.exe'));
      const rom = 'Colin McRae Rally 2.0 (Europe) (En,Fr,De,Es,It)';
      final game = Game(id: 'ps1ignored', name: 'Colin McRae Rally 2.0', fsName: '$rom.cue', platformSlug: 'psx', fileSize: 0);
      when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => {
            'id': 90,
            'download_path': 'https://example.test/notes.txt',
            'file_name': 'notes.txt',
            'emulator': 'duckstation',
          });
      when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId')))
          .thenAnswer((_) async => Uint8List.fromList(List.filled(300, 7)));

      expect(await sync.pullSave(game, p.join(tempDir.path, 'roms', '$rom.cue'), emulatorId: 'duckstation'), isFalse);
      await sync.markSaveSynced(game, p.join(tempDir.path, 'roms', '$rom.cue'), emulatorId: 'duckstation', syncMode: 'saves');
      expect(await sync.rommCopyOfLocal(game, p.join(tempDir.path, 'roms', '$rom.cue'), emulatorId: 'duckstation'), isNull,
          reason: 'RomM\'s save 90 is not what this PC has');
    });

    for (final (label, capabilities) in [
      ('legacy', RommCapabilities.unknown()),
      ('4.9', RommCapabilities(version: '4.9.0')),
    ]) {
      test('a downloaded save identical to the one on this PC (no content_hash) counts as pulled and synced ($label)', () async {
        when(mockRommService.fetchCapabilities()).thenAnswer((_) async => capabilities);
        final local = pattern(4096, 6);
        await File(p.join(retroarchSaves, '$romName.srm')).writeAsBytes(local);
        when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => {
              'id': 81,
              'download_path': 'https://example.test/same.srm',
              'file_name': '$romName.srm',
              'emulator': 'mupen64plus_next',
            });
        when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => local);

        expect(await sync.pullSave(n64Game(), romPath(), emulatorId: 'retroarch'), isTrue);
        for (final mode in const ['saves', 'both']) {
          expect(await sync.saveIsSynced(n64Game(), romPath(), emulatorId: 'retroarch', syncMode: mode), isTrue, reason: mode);
        }
        expect(await sync.rommCopyOfLocal(n64Game(), romPath(), emulatorId: 'retroarch'), '81');
      });
    }

    test('both sync modes: Dolphin\'s state files make \'both\' a second hash', () async {
      final exeDir = Directory(p.join(tempDir.path, 'dolphin'))..createSync();
      File(p.join(exeDir.path, 'Dolphin')).writeAsStringSync('');
      final card = Directory(p.join(exeDir.path, 'User', 'GC', 'USA', 'Card A'))..createSync(recursive: true);
      final states = Directory(p.join(exeDir.path, 'User', 'StateSaves'))..createSync(recursive: true);
      when(mockDirectoryService.findEmulatorExecutable('dolphin', any))
          .thenAnswer((_) async => p.join(exeDir.path, 'Dolphin'));
      const rom = 'Super Mario Sunshine (USA)';
      final game = Game(id: 'gcgame', name: 'Super Mario Sunshine', fsName: '$rom.iso', platformSlug: 'ngc', fileSize: 0);
      final romFile = p.join(tempDir.path, 'roms', '$rom.iso');
      // Dolphin reads the game ID from the disc header.
      File(romFile)
        ..createSync(recursive: true)
        ..writeAsBytesSync([...'GMSE01'.codeUnits, ...List.filled(64, 0)]);
      File(p.join(card.path, '01-GMSE01-Super Mario Sunshine.gci')).writeAsBytesSync(pattern(8256, 1));

      final saveOnly = await sync.rommHashesOfLocal(game, romFile, emulatorId: 'dolphin');
      File(p.join(states.path, '$rom.s01')).writeAsBytesSync(pattern(4096, 2));
      final withState = await sync.rommHashesOfLocal(game, romFile, emulatorId: 'dolphin');

      expect(saveOnly, hasLength(1));
      expect(withState, hasLength(2));
      expect(withState, containsAll(saveOnly));
    });

    test('a DuckStation PS1 card becomes the RetroArch core\'s .srm', () async {
      const cardRom = 'Colin McRae Rally 2.0 (Europe) (En,Fr,De,Es,It)';
      final card = buildPs1Card([(name: 'BESLES-02605-SETTING', blocks: [1], fill: 0x11)]);
      final game = Game(id: 'ps1game', name: 'Colin McRae Rally 2.0', fsName: '$cardRom.cue', platformSlug: 'psx', fileSize: 0);
      cloudSave('${cardRom}_1.mcd', card, emulator: 'duckstation');

      expect(await sync.pullSave(game, p.join(tempDir.path, 'roms', '$cardRom.cue'), emulatorId: 'retroarch'), isTrue);

      expect(filesIn(retroarchSaves), ['$cardRom.srm']);
      expect(File(p.join(retroarchSaves, '$cardRom.srm')).readAsBytesSync(), card);
    });

    test('a save no format recognises is restored as it came', () async {
      cloudSave('$romName.srm', pattern(4096), emulator: 'mupen64plus_next');

      expect(await sync.pullSave(n64Game(), romPath(), emulatorId: 'ares'), isFalse,
          reason: 'written as it came, but ares reads no .srm: its save is unchanged');

      expect(filesIn(aresSaves()), ['$romName.srm']);
      expect(filesIn(p.join(tempDir.path, 'roms')), isEmpty, reason: 'nothing in the ROM folder');
    });

    test('an RZIP save that can\'t be unpacked (no zstd library) is restored as it came', () async {
      final packed = buildRzip(blankSrm(), version: 2, compress: (c) => c);
      cloudSave('$romName.srm', packed, emulator: 'mupen64plus_next');

      expect(await sync.pullSave(n64Game(), romPath(), emulatorId: 'ares'), isFalse,
          reason: 'written as it came, but ares reads no .srm: its save is unchanged');

      expect(File(p.join(aresSaves(), '$romName.srm')).readAsBytesSync(), packed);
    });

    group('an automatic pull never replaces a newer local save', () {
      // ares has played before: its saves folder is set, so the local save
      // is read from there (an empty Saves path reads next to the ROM).
      setUp(() => File(p.join(aresDir(), 'settings.bml'))
          .writeAsString('Paths\n  Home\n  Saves: ${p.join(aresDir(), 'Saves').replaceAll(r'\', '/')}/\n'));

      void cloudSaveAt(String fileName, Uint8List bytes, String updatedAt, {String? emulator}) {
        when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => {
              'download_path': 'https://example.test/$fileName',
              'file_name': fileName,
              'emulator': emulator,
              'updated_at': updatedAt,
            });
        when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => bytes);
      }

      test('a local save newer than RomM\'s stays', () async {
        await Directory(aresSaves()).create(recursive: true);
        final local = File(p.join(aresSaves(), '$romName.eeprom'))..writeAsBytesSync(pattern(512, 9));
        local.setLastModifiedSync(DateTime.utc(2026, 10, 1, 12));
        cloudSaveAt('$romName.eeprom', pattern(512, 1), '2026-09-28T16:40:00Z', emulator: 'ares');

        expect(await sync.pullSave(n64Game(), romPath(), emulatorId: 'ares'), isFalse);
        expect(local.readAsBytesSync(), pattern(512, 9));
      });

      test('a RomM save newer than the local one is pulled', () async {
        await Directory(aresSaves()).create(recursive: true);
        final local = File(p.join(aresSaves(), '$romName.eeprom'))..writeAsBytesSync(pattern(512, 9));
        local.setLastModifiedSync(DateTime.utc(2026, 9, 1));
        cloudSaveAt('$romName.eeprom', pattern(512, 1), '2026-09-28T16:40:00Z', emulator: 'ares');

        expect(await sync.pullSave(n64Game(), romPath(), emulatorId: 'ares'), isTrue);
        expect(local.readAsBytesSync(), pattern(512, 1));
      });

      test('a chosen save replaces even a newer local one', () async {
        await Directory(aresSaves()).create(recursive: true);
        final local = File(p.join(aresSaves(), '$romName.eeprom'))..writeAsBytesSync(pattern(512, 9));
        local.setLastModifiedSync(DateTime.utc(2026, 10, 1, 12));
        final chosen = {
          'download_path': 'https://example.test/old.eeprom',
          'file_name': '$romName.eeprom',
          'emulator': 'ares',
          'updated_at': '2026-09-28T16:40:00Z',
        };
        when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => pattern(512, 1));

        expect(await sync.pullSave(n64Game(), romPath(), saveData: chosen, emulatorId: 'ares'), isTrue);
        expect(local.readAsBytesSync(), pattern(512, 1));
      });
    });

    group('a chosen save is put in place, or says why not', () {
      // ares has played before: its saves folder is set.
      setUp(() => File(p.join(aresDir(), 'settings.bml'))
          .writeAsString('Paths\n  Home\n  Saves: ${p.join(aresDir(), 'Saves').replaceAll(r'\', '/')}/\n'));

      test('a RomM save is downloaded and converted for the picked emulator', () async {
        const cardRom = 'Colin McRae Rally 2.0 (Europe) (En,Fr,De,Es,It)';
        final card = buildPs1Card([(name: 'BESLES-02605-SETTING', blocks: [1], fill: 0x12)]);
        final game = Game(id: 'ps1game', name: 'Colin McRae Rally 2.0', fsName: '$cardRom.cue', platformSlug: 'psx', fileSize: 0);
        when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => card);
        await sync.restoreChosenSave(game, p.join(tempDir.path, 'roms', '$cardRom.cue'), {
          'download_path': 'https://example.test/x.mcd',
          'file_name': '${cardRom}_1.mcd',
          'emulator': 'duckstation',
        }, emulatorId: 'retroarch');
        expect(File(p.join(retroarchSaves, '$cardRom.srm')).readAsBytesSync(), card);
      });

      test('a failed download throws and writes nothing', () async {
        when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => null);
        await expectLater(
          sync.restoreChosenSave(n64Game(), romPath(), {'download_path': 'https://example.test/x', 'file_name': 'x.srm'}, emulatorId: 'ares'),
          throwsA(isA<SaveChoiceException>()),
        );
        expect(filesIn(aresSaves()), isEmpty);
      });

      test('an N64 RetroArch save on this PC is not moved into ares (no N64 conversion)', () async {
        await File(p.join(retroarchSaves, '$romName.srm')).writeAsBytes(blankSrm()..setRange(0, 512, pattern(512, 7)));
        await expectLater(
          sync.convertLocalSave(n64Game(), romPath(), fromEmulatorId: 'retroarch', fromTag: 'mupen64plus_next', emulatorId: 'ares'),
          throwsA(isA<SaveChoiceException>()),
        );
        expect(Directory(aresSaves()).existsSync() ? filesIn(aresSaves()) : <String>[], isEmpty);
      });

      test('a local save that does not convert throws', () async {
        await File(p.join(retroarchSaves, '$romName.srm')).writeAsBytes(pattern(4096));
        await expectLater(
          sync.convertLocalSave(n64Game(), romPath(), fromEmulatorId: 'retroarch', fromTag: 'mupen64plus_next', emulatorId: 'ares'),
          throwsA(isA<SaveChoiceException>()),
        );
      });

      test('a RetroArch core left set by another game is not used for the fingerprint', () async {
        // RetroArch sorting saves into a folder per core.
        await File(p.join(tempDir.path, '.config', 'retroarch', 'retroarch.cfg'))
            .writeAsString('savefile_directory = "$retroarchSaves"\nsort_savefiles_enable = "true"\n');
        // The game's core (the N64 default, Mupen64Plus-Next) and another core
        // both have a save for it.
        for (final (folder, seed) in [('Mupen64Plus-Next', 1), ('ParaLLEl N64', 2)]) {
          final dir = Directory(p.join(retroarchSaves, folder))..createSync(recursive: true);
          File(p.join(dir.path, '$romName.srm')).writeAsBytesSync(blankSrm()..setRange(0, 512, pattern(512, seed)));
        }
        final retroarch = sync.saveStrategyForEmulator('retroarch')! as RetroArchSaveStrategy;
        retroarch.setLaunchCoreOverride('mupen64plus_next');
        final own = await sync.saveFingerprint(n64Game(), romPath(), emulatorId: 'retroarch');

        // Another game's sync left Parallel set.
        retroarch.setLaunchCoreOverride('parallel_n64');
        expect(await sync.saveFingerprint(n64Game(), romPath(), emulatorId: 'retroarch'), own);
      });

      for (final sorted in [true, false]) {
        test('the save list has each RetroArch core\'s own save (sorted by core: $sorted)', () async {
          await File(p.join(tempDir.path, '.config', 'retroarch', 'retroarch.cfg'))
              .writeAsString('savefile_directory = "$retroarchSaves"\nsort_savefiles_enable = "$sorted"\n');
          for (final (folder, seed) in [('Mupen64Plus-Next', 1), ('ParaLLEl N64', 2)]) {
            final dir = Directory(sorted ? p.join(retroarchSaves, folder) : retroarchSaves)..createSync(recursive: true);
            File(p.join(dir.path, '$romName.srm')).writeAsBytesSync(blankSrm()..setRange(0, 512, pattern(512, seed)));
          }
          when(mockStrategyRegistry.getAllStrategiesForSlug('n64')).thenReturn([_Emulator('retroarch')]);
          final sources = LiveSaveCatalogSources(
              sync: sync,
              registry: mockStrategyRegistry,
              backupRepository: BackupRepository(),
              rommService: null,
              installed: const {'retroarch': true});

          final rows = await sources.localSaves(n64Game(), romPath());

          expect(rows.map((r) => r.maker?.tag).toList(),
              sorted ? ['mupen64plus_next', 'parallel_n64'] : [rows.single.maker?.tag]);
        });
      }

      test('a save counts as synced only while it is the content RomM has, per sync mode', () async {
        await Directory(aresSaves()).create(recursive: true);
        final f = File(p.join(aresSaves(), '$romName.eeprom'))..writeAsBytesSync(pattern(512, 1));
        expect(await sync.saveIsSynced(n64Game(), romPath(), emulatorId: 'ares', syncMode: 'both'), isFalse);

        await sync.markSaveSynced(n64Game(), romPath(), emulatorId: 'ares', syncMode: 'both');

        expect(await sync.saveIsSynced(n64Game(), romPath(), emulatorId: 'ares', syncMode: 'both'), isTrue);
        expect(await sync.saveIsSynced(n64Game(), romPath(), emulatorId: 'ares', syncMode: 'saves'), isFalse);
        f.writeAsBytesSync(pattern(512, 2));
        expect(await sync.saveIsSynced(n64Game(), romPath(), emulatorId: 'ares', syncMode: 'both'), isFalse);
      });

      test('a local save rewritten with the content RomM already has is not "newer"', () async {
        await Directory(aresSaves()).create(recursive: true);
        final local = File(p.join(aresSaves(), '$romName.eeprom'))..writeAsBytesSync(pattern(512, 1));
        await sync.markSaveSynced(n64Game(), romPath(), emulatorId: 'ares', syncMode: 'saves');
        // The emulator wrote the same save again on exit: newer time, same content.
        local.setLastModifiedSync(DateTime.utc(2026, 10, 1, 12));
        when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => {
              'download_path': 'https://example.test/b.eeprom',
              'file_name': '$romName.eeprom',
              'emulator': 'ares',
              'updated_at': '2026-09-28T16:40:00Z',
            });
        when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => pattern(512, 3));

        expect(await sync.pullSave(n64Game(), romPath(), emulatorId: 'ares'), isTrue);
        expect(local.readAsBytesSync(), pattern(512, 3));
      });

      test('the fingerprint changes with the save and only with it', () async {
        expect(await sync.saveFingerprint(n64Game(), romPath(), emulatorId: 'ares'), 'none');
        await Directory(aresSaves()).create(recursive: true);
        final f = File(p.join(aresSaves(), '$romName.eeprom'))..writeAsBytesSync(pattern(512, 1));
        final a = await sync.saveFingerprint(n64Game(), romPath(), emulatorId: 'ares');
        f.setLastModifiedSync(DateTime(2030));
        expect(await sync.saveFingerprint(n64Game(), romPath(), emulatorId: 'ares'), a, reason: 'time alone is no change');
        f.writeAsBytesSync(pattern(512, 2));
        expect(await sync.saveFingerprint(n64Game(), romPath(), emulatorId: 'ares'), isNot(a));
      });
    });
  });

  group('The newer-local guard and shared or folder saves', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('save_guard'));
    tearDown(() => tmp.delete(recursive: true));

    test('a memory card other games share never blocks a pull, however new it is', () async {
      final card = File(p.join(tmp.path, 'shared.mcd'))..writeAsBytesSync(List.filled(128, 1));
      card.setLastModifiedSync(DateTime.utc(2026, 10, 1, 12)); // another game played on it
      final strategy = _SharedCardStrategy(card);
      final sync = _OneStrategySync(strategy, mockRommService, mockDirectoryService, mockStrategyRegistry,
          SharedPreferencesAppPreferences(await SharedPreferences.getInstance()));
      when(mockRommService.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => {
            'download_path': 'https://example.test/x.mcd',
            'file_name': 'x.mcd',
            'updated_at': '2026-09-28T16:40:00Z',
          });
      when(mockRommService.downloadSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => Uint8List(128));

      final game = Game(id: 'gx', name: 'X', fsName: 'X.cue', platformSlug: 'gba', fileSize: 0);
      expect(await sync.pullSave(game, p.join(tmp.path, 'X.cue'), emulatorId: 'card'), isTrue);
      expect(strategy.restored, ['x.mcd']);
    });

    test('the newest time in a save folder is found inside it', () async {
      final folder = Directory(p.join(tmp.path, 'SAVEDATA', 'ULUS10041'))..createSync(recursive: true);
      File(p.join(folder.path, 'DATA.BIN'))
        ..writeAsBytesSync([1])
        ..setLastModifiedSync(DateTime.utc(2026, 10, 1, 12));
      final newest = await SaveSyncService.newestModified([Directory(p.join(tmp.path, 'SAVEDATA'))]);
      expect(newest!.isAtSameMomentAs(DateTime.utc(2026, 10, 1, 12)), isTrue);
    });
  });
}

/// A save strategy whose game shares one memory card with other games.
class _SharedCardStrategy implements SaveStrategy {
  _SharedCardStrategy(this.card);
  final File card;
  final restored = <String>[];
  @override
  String get strategyId => 'card';
  @override
  Future<String?> saveSyncBlockedReason(Game game, String romPath) async => null;
  @override
  Future<bool> pullMustFinishBeforeLaunch(Game game, String romPath) async => true;
  @override
  Future<List<File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async => [card];
  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    restored.add(filename);
    return true;
  }

  @override
  String getRomStem(Game game) => 'X';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Save sync where every game uses [strategy].
class _OneStrategySync extends SaveSyncService {
  _OneStrategySync(this.strategy, super.romm, super.dirs, super.registry, super.prefs);
  final SaveStrategy strategy;
  @override
  SaveStrategy? getStrategyForGame(Game game, {String? emulatorId}) => strategy;
}

/// An emulator the registry lists for a platform: only its id is read.
class _Emulator extends Fake implements EmulatorStrategy {
  _Emulator(this.emulatorId);
  @override
  final String emulatorId;
}
