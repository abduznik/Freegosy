import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/emulator/firmware_service.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';

import 'firmware_service_test.mocks.dart';

class MockEmulatorStrategy extends Mock implements EmulatorStrategy {
  @override
  String get emulatorId => 'test_emulator';
}

@GenerateMocks([RommService, DirectoryService, StrategyRegistry])
void main() {
  late FirmwareService service;
  late MockRommService mockRommService;
  late MockDirectoryService mockDirectoryService;
  late MockStrategyRegistry mockStrategyRegistry;

  setUp(() {
    mockRommService = MockRommService();
    mockDirectoryService = MockDirectoryService();
    mockStrategyRegistry = MockStrategyRegistry();
    service = FirmwareService(mockRommService, mockDirectoryService, mockStrategyRegistry);
  });

  group('FirmwareService', () {
    test('syncAllFirmware() downloads and places firmware correctly', () async {
      final tempDir = await Directory.systemTemp.createTemp('firmware_test');
      final biosDir = p.join(tempDir.path, 'BIOS');
      await Directory(biosDir).create();

      final firmware = Firmware(
        id: 1,
        fileName: 'test_bios.bin',
        fileSizeBytes: 100,
      );

      final platform = Platform(
        id: 1,
        name: 'Test Platform',
        slug: 'test_platform',
        firmware: [firmware],
      );

      final mockStrategy = MockEmulatorStrategy();

      when(mockRommService.getPlatforms()).thenAnswer((_) async => [platform]);
      when(mockStrategyRegistry.getStrategyForSlug('test_platform')).thenReturn(mockStrategy);
      when(mockDirectoryService.getEmulatorBiosDirectory('test_emulator')).thenAnswer((_) async => biosDir);
      when(mockRommService.downloadFirmware(firmware, onProgress: anyNamed('onProgress')))
          .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

      await service.syncAllFirmware();

      final destFile = File(p.join(biosDir, 'test_bios.bin'));
      expect(await destFile.exists(), isTrue);
      expect(await destFile.readAsBytes(), equals([1, 2, 3]));

      await tempDir.delete(recursive: true);
    });

    test('syncFirmwareForPlatform() syncs specifically for one platform', () async {
       final tempDir = await Directory.systemTemp.createTemp('firmware_test_single');
      final biosDir = p.join(tempDir.path, 'BIOS');
      await Directory(biosDir).create();

      final firmware = Firmware(
        id: 2,
        fileName: 'platform_bios.bin',
        fileSizeBytes: 200,
      );

      final platform = Platform(
        id: 2,
        name: 'Single Platform',
        slug: 'single_slug',
        firmware: [firmware],
      );

      final mockStrategy = MockEmulatorStrategy();

      when(mockRommService.getPlatforms()).thenAnswer((_) async => [platform]);
      when(mockStrategyRegistry.getStrategyForSlug('single_slug')).thenReturn(mockStrategy);
      when(mockDirectoryService.getEmulatorBiosDirectory('test_emulator')).thenAnswer((_) async => biosDir);
      when(mockRommService.downloadFirmware(firmware, onProgress: anyNamed('onProgress')))
          .thenAnswer((_) async => Uint8List.fromList([4, 5, 6]));

      await service.syncFirmwareForPlatform('single_slug');

      final destFile = File(p.join(biosDir, 'platform_bios.bin'));
      expect(await destFile.exists(), isTrue);
      expect(await destFile.readAsBytes(), equals([4, 5, 6]));

      await tempDir.delete(recursive: true);
    });
  });

  group('Firmware filePath subdirectory preservation', () {
    test('uses filePath for subdirectory structure when provided', () async {
      final tempDir = await Directory.systemTemp.createTemp('firmware_subdir_test');
      final biosDir = p.join(tempDir.path, 'BIOS');
      await Directory(biosDir).create();

      // Firmware with filePath as directory (real RomM servers return file_path as directory,
      // file_name as filename). E.g. Flycast expects dc/dc_boot.bin in BIOS/dc/dc_boot.bin.
      final firmware = Firmware(
        id: 3,
        fileName: 'dc_boot.bin',
        filePath: 'dc',
        fileSizeBytes: 100,
      );

      final platform = Platform(
        id: 3,
        name: 'Dreamcast',
        slug: 'dc',
        firmware: [firmware],
      );

      final mockStrategy = MockEmulatorStrategy();

      when(mockRommService.getPlatforms()).thenAnswer((_) async => [platform]);
      when(mockStrategyRegistry.getStrategyForSlug('dc')).thenReturn(mockStrategy);
      when(mockDirectoryService.getEmulatorBiosDirectory('test_emulator')).thenAnswer((_) async => biosDir);
      when(mockRommService.downloadFirmware(firmware, onProgress: anyNamed('onProgress')))
          .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

      await service.syncAllFirmware();

      // Should be in system/dc/dc_boot.bin, NOT system/dc_boot.bin
      final correctPath = File(p.join(biosDir, 'dc', 'dc_boot.bin'));
      final wrongPath = File(p.join(biosDir, 'dc_boot.bin'));

      expect(await correctPath.exists(), isTrue,
          reason: 'BIOS should be in dc/ subdirectory');
      expect(await wrongPath.exists(), isFalse,
          reason: 'BIOS should NOT be flat in system root');

      await tempDir.delete(recursive: true);
    });

    test('falls back to fileName when filePath is null', () async {
      final tempDir = await Directory.systemTemp.createTemp('firmware_flat_test');
      final biosDir = p.join(tempDir.path, 'BIOS');
      await Directory(biosDir).create();

      final firmware = Firmware(
        id: 4,
        fileName: 'gba_bios.bin',
        filePath: null,
        fileSizeBytes: 100,
      );

      final platform = Platform(
        id: 4,
        name: 'GBA',
        slug: 'gba',
        firmware: [firmware],
      );

      final mockStrategy = MockEmulatorStrategy();

      when(mockRommService.getPlatforms()).thenAnswer((_) async => [platform]);
      when(mockStrategyRegistry.getStrategyForSlug('gba')).thenReturn(mockStrategy);
      when(mockDirectoryService.getEmulatorBiosDirectory('test_emulator')).thenAnswer((_) async => biosDir);
      when(mockRommService.downloadFirmware(firmware, onProgress: anyNamed('onProgress')))
          .thenAnswer((_) async => Uint8List.fromList([4, 5, 6]));

      await service.syncAllFirmware();

      final destFile = File(p.join(biosDir, 'gba_bios.bin'));
      expect(await destFile.exists(), isTrue);

      await tempDir.delete(recursive: true);
    });

    test('falls back to fileName when filePath is empty string', () async {
      final tempDir = await Directory.systemTemp.createTemp('firmware_empty_path_test');
      final biosDir = p.join(tempDir.path, 'BIOS');
      await Directory(biosDir).create();

      final firmware = Firmware(
        id: 5,
        fileName: 'psx_bios.bin',
        filePath: '',
        fileSizeBytes: 100,
      );

      final platform = Platform(
        id: 5,
        name: 'PS1',
        slug: 'psx',
        firmware: [firmware],
      );

      final mockStrategy = MockEmulatorStrategy();

      when(mockRommService.getPlatforms()).thenAnswer((_) async => [platform]);
      when(mockStrategyRegistry.getStrategyForSlug('psx')).thenReturn(mockStrategy);
      when(mockDirectoryService.getEmulatorBiosDirectory('test_emulator')).thenAnswer((_) async => biosDir);
      when(mockRommService.downloadFirmware(firmware, onProgress: anyNamed('onProgress')))
          .thenAnswer((_) async => Uint8List.fromList([7, 8, 9]));

      await service.syncAllFirmware();

      final destFile = File(p.join(biosDir, 'psx_bios.bin'));
      expect(await destFile.exists(), isTrue);

      await tempDir.delete(recursive: true);
    });

    test('real-world firmware: filePath is directory path (e.g. psp/bios)', () async {
      final tempDir = await Directory.systemTemp.createTemp('firmware_realworld_test');
      final biosDir = p.join(tempDir.path, 'BIOS');
      await Directory(biosDir).create();

      // Real RomM servers return file_path as directory, file_name as filename.
      // E.g. psp/bios/cheat.db should be placed at BIOS/psp/bios/cheat.db
      final firmware = Firmware(
        id: 6,
        fileName: 'cheat.db',
        filePath: 'psp/bios',
        fileSizeBytes: 200,
      );

      final platform = Platform(
        id: 6,
        name: 'PSP',
        slug: 'psp',
        firmware: [firmware],
      );

      final mockStrategy = MockEmulatorStrategy();

      when(mockRommService.getPlatforms()).thenAnswer((_) async => [platform]);
      when(mockStrategyRegistry.getStrategyForSlug('psp')).thenReturn(mockStrategy);
      when(mockDirectoryService.getEmulatorBiosDirectory('test_emulator')).thenAnswer((_) async => biosDir);
      when(mockRommService.downloadFirmware(firmware, onProgress: anyNamed('onProgress')))
          .thenAnswer((_) async => Uint8List.fromList([10, 11, 12]));

      await service.syncAllFirmware();

      // Should be in BIOS/psp/bios/cheat.db, NOT BIOS/psp/bios (wrong) or BIOS/cheat.db (wrong)
      final correctPath = File(p.join(biosDir, 'psp', 'bios', 'cheat.db'));
      final wrongDirPath = File(p.join(biosDir, 'psp', 'bios'));
      final wrongFlatPath = File(p.join(biosDir, 'cheat.db'));

      expect(await correctPath.exists(), isTrue,
          reason: 'Firmware should be in psp/bios/cheat.db subdirectory');
      expect(await wrongDirPath.exists(), isFalse,
          reason: 'Firmware should NOT be named as a directory');
      expect(await wrongFlatPath.exists(), isFalse,
          reason: 'Firmware should NOT be flat in BIOS root');

      await tempDir.delete(recursive: true);
    });
  });
}
