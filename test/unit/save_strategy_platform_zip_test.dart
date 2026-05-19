import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';

import 'save_sync_service_test.mocks.dart';

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
    
    when(mockDirectoryService.getEmulatorAppSupportDirectory(any, platformSlug: anyNamed('platformSlug')))
        .thenAnswer((_) async => '/nonexistent_directory_for_testing');

    final sysTemp = Directory.systemTemp.path;
    when(mockDirectoryService.getEmulatorDirectory('temp'))
        .thenAnswer((_) async => sysTemp);
    
    final prefs = await SharedPreferences.getInstance();
    when(mockRommService.getLatestSave(any)).thenAnswer((_) async => null);
    service = SaveSyncService(mockRommService, mockDirectoryService, mockStrategyRegistry, prefs);
  });

  group('SaveStrategy shouldZip Platform-Specific Settings', () {
    test('retroarch core platform snes/nes/n64 should return false for shouldZip', () {
      final strategy = service.getStrategyForSlug('snes');
      expect(strategy, isNotNull);
      expect(strategy!.shouldZip, isFalse);
    });

    test('melonds NDS core should return false for shouldZip', () {
      final strategy = service.getStrategyForSlug('nds');
      expect(strategy, isNotNull);
      expect(strategy!.shouldZip, isFalse);
    });

    test('mgba core should return false for shouldZip', () {
      final strategy = service.getStrategyForSlug('gba');
      expect(strategy, isNotNull);
      expect(strategy!.shouldZip, isFalse);
    });

    test('dolphin GC/Wii core should return false for shouldZip', () {
      final strategy = service.getStrategyForSlug('gc');
      expect(strategy, isNotNull);
      expect(strategy!.shouldZip, isFalse);
    });

    test('windows native core should return true for shouldZip', () {
      final strategy = service.getStrategyForSlug('windows');
      expect(strategy, isNotNull);
      expect(strategy!.shouldZip, isTrue);
    });

    test('ryujinx Switch core should return true for shouldZip', () {
      final strategy = service.getStrategyForSlug('switch');
      expect(strategy, isNotNull);
      expect(strategy!.shouldZip, isTrue);
    });

    test('eden Switch core should return true for shouldZip', () {
      final strategy = service.edenSaveStrategy;
      expect(strategy.shouldZip, isTrue);
    });

    test('pcsx2 PS2 core should return true for shouldZip', () {
      final strategy = service.getStrategyForSlug('ps2');
      expect(strategy, isNotNull);
      expect(strategy!.shouldZip, isTrue);
    });
  });

  group('SaveSyncService pushSaves platform-specific zipping behavior', () {
    test('pushSaves() uploads raw unzipped save file directly for unzipped platforms (e.g. mGBA)', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_sync_unzipped_test');
      final romPath = p.join(tempDir.path, 'game.gba');
      
      // Create a save file and a state file to simulate multiple files
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      await saveFile.writeAsString('sav content');
      final stateFile = File(p.join(tempDir.path, 'game.state1'));
      await stateFile.writeAsString('state content');

      final game = Game(id: 'game1', name: 'game', platformSlug: 'gba', fileSize: 0);

      File? uploadedFile;
      String? uploadedFilename;

      when(mockRommService.uploadSave(
        any, 
        any, 
        slot: anyNamed('slot'), 
        screenshotFile: anyNamed('screenshotFile'), 
        overrideFilename: anyNamed('overrideFilename')
      )).thenAnswer((inv) async {
        uploadedFile = inv.positionalArguments[1] as File;
        uploadedFilename = inv.namedArguments[#overrideFilename] as String?;
        return true;
      });
      when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount'))).thenAnswer((_) async {});

      final ok = await service.pushSaves(game, romPath);
      
      expect(ok, isTrue);
      expect(uploadedFile, isNotNull);
      expect(uploadedFilename, 'game.sav');
      
      // Verify that the uploaded file is unzipped and contains the raw save content
      final content = await uploadedFile!.readAsString();
      expect(content, 'sav content');
      
      await tempDir.delete(recursive: true);
    });

    test('pushSaves() bundles files into zip for zipped platforms (e.g. Ryujinx)', () async {
      // Ryujinx saves are normally stored inside user directories which are mocked out.
      // Let's mock RyujinxSaveStrategy to return files.
      // Since it's easier to mock the getSaveFilesWithScreenshots via a customized test save strategy,
      // let's do a direct test of the zipping branch in SaveSyncService by utilizing a platform
      // that is mapped to a zipped strategy, e.g. windows strategy.
      // Windows strategy gets saves from directories described by PcGamingWiki, but we can override
      // the path via SharedPreferences override or mock it.
      // Let's verify that a platform with shouldZip = true gets zipped when there are multiple files.
      final tempDir = await Directory.systemTemp.createTemp('save_sync_zipped_test');
      final romPath = p.join(tempDir.path, 'game.exe');
      
      final game = Game(id: 'game_win', name: 'PC Game', platformSlug: 'windows', fileSize: 0);

      // Windows strategy reads overrides from prefs
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('win_save_game_win', tempDir.path);
      service.windowsSaveStrategy.loadPersistedOverrides();

      // Create multiple save files
      final file1 = File(p.join(tempDir.path, 'save1.dat'));
      await file1.writeAsString('data1');
      final file2 = File(p.join(tempDir.path, 'save2.dat'));
      await file2.writeAsString('data2');

      File? uploadedFile;
      String? uploadedFilename;
      List<int>? uploadedBytes;

      when(mockRommService.uploadSave(
        any, 
        any, 
        slot: anyNamed('slot'), 
        screenshotFile: anyNamed('screenshotFile'), 
        overrideFilename: anyNamed('overrideFilename')
      )).thenAnswer((inv) async {
        uploadedFile = inv.positionalArguments[1] as File;
        uploadedFilename = inv.namedArguments[#overrideFilename] as String?;
        if (uploadedFile != null && uploadedFile!.existsSync()) {
          uploadedBytes = await uploadedFile!.readAsBytes();
        }
        return true;
      });
      when(mockRommService.pruneOldSaves(any, keepCount: anyNamed('keepCount'))).thenAnswer((_) async {});

      final ok = await service.pushSaves(game, romPath);
      
      expect(ok, isTrue);
      expect(uploadedFile, isNotNull);
      expect(uploadedFilename, 'PC Game.zip');
      expect(uploadedBytes, isNotNull);
      
      // Verify that the uploaded file is indeed a ZIP archive and contains the files
      final archive = ZipDecoder().decodeBytes(uploadedBytes!);
      final filenames = archive.map((e) => e.name).toList();
      
      expect(filenames.any((name) => name.endsWith('save1.dat')), isTrue);
      expect(filenames.any((name) => name.endsWith('save2.dat')), isTrue);
      expect(filenames.any((name) => name.endsWith('freegosy_sync.txt')), isTrue);
      
      await tempDir.delete(recursive: true);
    });
  });

  group('Unzipped strategies restoreSave backward/cross-compatibility', () {
    test('RetroArchSaveStrategy successfully extracts and restores a zipped save file', () async {
      final tempDir = await Directory.systemTemp.createTemp('retroarch_restore_zip');
      final romPath = p.join(tempDir.path, 'game.sfc');
      
      final strategy = service.getStrategyForSlug('snes');
      expect(strategy, isNotNull);

      // Create a ZIP in memory containing a save file
      final encoder = ZipEncoder();
      final archive = Archive();
      final saveFileContent = 'zipped srm content';
      archive.addFile(ArchiveFile('game.srm', saveFileContent.length, saveFileContent.codeUnits));
      final zipBytes = encoder.encode(archive) as Uint8List;

      // Mock search or exec paths to direct to tempDir
      when(mockDirectoryService.findEmulatorExecutable(any, any))
          .thenAnswer((_) async => tempDir.path);

      final game = Game(id: 'game1', name: 'game', platformSlug: 'snes', fileSize: 0);
      final ok = await strategy!.restoreSave(game, romPath, zipBytes, 'game.zip');
      
      expect(ok, isTrue);
      
      // Verify the file was correctly extracted to saves/SNES/game.srm
      final expectedPath = p.join(tempDir.path, 'saves', 'SNES', 'game.srm');
      final restoredFile = File(expectedPath);
      expect(restoredFile.existsSync(), isTrue);
      expect(await restoredFile.readAsString(), saveFileContent);

      await tempDir.delete(recursive: true);
    });
  });
}
