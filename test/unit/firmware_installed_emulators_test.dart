import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/emulator/firmware_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';

import 'firmware_service_test.mocks.dart';

class _Strategy extends Mock implements EmulatorStrategy {
  final String _id;
  _Strategy(this._id);
  @override
  String get emulatorId => _id;
}

/// "Sync BIOS" for every installed emulator, not only the platform default.
// syncAllFirmware tests use made-up emulator ids and file names so the real
// BIOS registry (subfolders, known MD5s) doesn't change where files land.
void main() {
  late MockRommService romm;
  late MockDirectoryService dirs;
  late MockStrategyRegistry registry;
  late FirmwareService service;
  late Directory tmp;

  setUp(() async {
    romm = MockRommService();
    dirs = MockDirectoryService();
    registry = MockStrategyRegistry();
    service = FirmwareService(romm, dirs, registry);
    tmp = await Directory.systemTemp.createTemp('fw_installed');
    when(dirs.getEmulatorBiosDirectory(any)).thenAnswer((i) async => p.join(tmp.path, i.positionalArguments.first as String));
    when(romm.downloadFirmware(any, onProgress: anyNamed('onProgress'))).thenAnswer((_) async => Uint8List.fromList([9, 9]));
  });

  tearDown(() => tmp.delete(recursive: true));

  Platform platform(String slug, List<String> files) => Platform(
        id: slug.hashCode,
        name: slug,
        slug: slug,
        firmware: [for (var i = 0; i < files.length; i++) Firmware(id: i, fileName: files[i], fileSizeBytes: 2)],
      );

  bool placed(String emulatorId, String file) => File(p.join(tmp.path, emulatorId, file)).existsSync();

  group('emulatorIdsForFirmwareSync', () {
    test('keeps registry order and drops duplicates', () {
      when(registry.getAllStrategiesForSlug('psx')).thenReturn([_Strategy('duckstation'), _Strategy('retroarch'), _Strategy('duckstation')]);
      expect(service.emulatorIdsForFirmwareSync('psx', {'retroarch', 'duckstation'}), ['duckstation', 'retroarch']);
    });

    test('without an installed set, falls back to the platform default emulator', () {
      when(registry.getStrategyForSlug('psx')).thenReturn(_Strategy('duckstation'));
      expect(service.emulatorIdsForFirmwareSync('psx', null), ['duckstation']);
      verifyNever(registry.getAllStrategiesForSlug(any));
    });

    test('without an installed set and no emulator for the platform, returns nothing', () {
      when(registry.getStrategyForSlug('unknown')).thenReturn(null);
      expect(service.emulatorIdsForFirmwareSync('unknown', null), isEmpty);
    });

    test('an empty installed set syncs nothing', () {
      when(registry.getAllStrategiesForSlug('psx')).thenReturn([_Strategy('duckstation')]);
      expect(service.emulatorIdsForFirmwareSync('psx', <String>{}), isEmpty);
    });
  });

  group('syncAllFirmware(installedEmulatorIds:)', () {
    test('each platform goes only to its own installed emulators', () async {
      when(romm.getPlatforms()).thenAnswer((_) async => [platform('test_psx', ['test_bios_a.bin']), platform('test_dc', ['test_bios_b.bin'])]);
      when(registry.getAllStrategiesForSlug('test_psx')).thenReturn([_Strategy('emu_a'), _Strategy('emu_not_installed')]);
      when(registry.getAllStrategiesForSlug('test_dc')).thenReturn([_Strategy('emu_b')]);

      await service.syncAllFirmware(installedEmulatorIds: {'emu_a', 'emu_b'});

      expect(placed('emu_a', 'test_bios_a.bin'), isTrue);
      expect(placed('emu_b', 'test_bios_b.bin'), isTrue);
      expect(placed('emu_b', 'test_bios_a.bin'), isFalse);
      expect(placed('emu_a', 'test_bios_b.bin'), isFalse);
      verifyNever(dirs.getEmulatorBiosDirectory('emu_not_installed'));
    });

    test('platforms without firmware are skipped without asking the registry', () async {
      when(romm.getPlatforms()).thenAnswer((_) async => [platform('snes', [])]);

      await service.syncAllFirmware(installedEmulatorIds: {'retroarch'});

      verifyNever(registry.getAllStrategiesForSlug(any));
      verifyNever(romm.downloadFirmware(any, onProgress: anyNamed('onProgress')));
    });

    test('a file already in an emulator folder is not downloaded again', () async {
      when(romm.getPlatforms()).thenAnswer((_) async => [platform('test_psx', ['test_bios_a.bin'])]);
      when(registry.getAllStrategiesForSlug('test_psx')).thenReturn([_Strategy('emu_a'), _Strategy('emu_c')]);
      final existing = File(p.join(tmp.path, 'emu_a', 'test_bios_a.bin'));
      await existing.create(recursive: true);
      await existing.writeAsBytes([1]);

      await service.syncAllFirmware(installedEmulatorIds: {'emu_a', 'emu_c'});

      expect(existing.readAsBytesSync(), [1]);
      expect(placed('emu_c', 'test_bios_a.bin'), isTrue);
      verify(romm.downloadFirmware(any, onProgress: anyNamed('onProgress'))).called(1);
    });

    test('reports progress for every emulator it downloads to', () async {
      when(romm.getPlatforms()).thenAnswer((_) async => [platform('test_psx', ['test_bios_a.bin'])]);
      when(registry.getAllStrategiesForSlug('test_psx')).thenReturn([_Strategy('emu_a'), _Strategy('emu_c')]);
      final started = <String>[];

      await service.syncAllFirmware(
        installedEmulatorIds: {'emu_a', 'emu_c'},
        onProgress: (name, received, total) {
          if (received == 0) started.add(name);
        },
      );

      expect(started, ['test_bios_a.bin', 'test_bios_a.bin']);
    });

    test('a RomM error is swallowed rather than crashing the dialog', () async {
      when(romm.getPlatforms()).thenThrow(Exception('offline'));
      await service.syncAllFirmware(installedEmulatorIds: {'emu_a'});
    });
  });
}
