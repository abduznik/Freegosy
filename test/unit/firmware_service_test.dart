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
}
