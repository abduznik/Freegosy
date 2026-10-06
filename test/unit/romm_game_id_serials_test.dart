import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/duckstation_save_strategy.dart';
import 'package:freegosy/core/save/strategies/pcsx2_save_strategy.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_id_test_env.dart';

void main() {
  late Directory base;
  setUp(() async => base = await Directory.systemTemp.createTemp('romm_serials'));
  tearDown(() => base.delete(recursive: true));

  group('PCSX2', () {
    Future<(Pcsx2SaveStrategy, SpySerialExtractionService)> strategy() async {
      final exeDir = p.join(base.path, 'pcsx2');
      await Directory(p.join(exeDir, 'memcards')).create(recursive: true);
      final exe = p.join(exeDir, 'pcsx2-qt.exe');
      await File(exe).writeAsString('');
      final ds = await StubDirectoryService.create(exePath: exe);
      final spy = SpySerialExtractionService(ds, await ds.appPrefs());
      return (
        Pcsx2SaveStrategy(ds, await ds.appPrefs(),
            platform: const PlatformInfo('windows', environment: {}), serialExtractionService: spy),
        spy
      );
    }

    test('the per-game save folder is found by RomM\'s serial, without reading the ROM', () async {
      final (pcsx2, spy) = await strategy();
      final perGame = Directory(p.join(base.path, 'pcsx2', 'saves', 'SCUS-97113'))..createSync(recursive: true);
      File(p.join(perGame.path, 'data.bin')).writeAsBytesSync(List.filled(150, 2));

      final files = await pcsx2.getSaveFiles(
        Game(id: 'g1', name: 'Ico', platformSlug: 'ps2', fileSize: 0, titleId: 'SCUS-97113'),
        p.join(base.path, 'Ico.chd'),
      );

      expect(files.map((f) => f.path), [perGame.path]);
      expect(spy.reads, 0);
    });

    test('RomM\'s serial is normalised like a read one (slus_203.12 → SLUS-20312)', () async {
      final (pcsx2, spy) = await strategy();
      final perGame = Directory(p.join(base.path, 'pcsx2', 'saves', 'SLUS-20312'))..createSync(recursive: true);
      File(p.join(perGame.path, 'data.bin')).writeAsBytesSync(List.filled(150, 2));

      final files = await pcsx2.getSaveFiles(
        Game(id: 'g2', name: 'Game', platformSlug: 'ps2', fileSize: 0, titleId: ' slus_203.12 '),
        p.join(base.path, 'Game.iso'),
      );

      expect(files.map((f) => f.path), [perGame.path]);
      expect(spy.reads, 0);
    });

    test('without RomM\'s serial the ROM is read, as before', () async {
      final (pcsx2, spy) = await strategy();
      await pcsx2.getSaveFiles(Game(id: 'g3', name: 'Game', platformSlug: 'ps2', fileSize: 0), p.join(base.path, 'Game.iso'));
      expect(spy.reads, greaterThan(0));
    });
  });

  group('DuckStation', () {
    test('the state matcher uses RomM\'s serial, without reading the ROM', () async {
      final ds = await StubDirectoryService.create(appSupport: base.path);
      final spy = SpySerialExtractionService(ds, await ds.appPrefs());
      final duck = DuckstationSaveStrategy(ds, await ds.appPrefs(),
          platform: const PlatformInfo('windows', environment: {}), serialExtractionService: spy);

      final matches = await duck.stateFileMatcher(
        Game(id: 'd1', name: 'Chrono Cross', platformSlug: 'psx', fileSize: 0, titleId: 'SLUS-01041'),
        p.join(base.path, 'Chrono Cross.chd'),
      );

      expect(matches, isNotNull);
      expect(matches!('SLUS-01041_1.sav'), isTrue);
      expect(matches('SLUS-00594_1.sav'), isFalse);
      expect(spy.reads, 0);
    });
  });

  group('RomM serial: where the ROM is still read', () {
    Future<(Pcsx2SaveStrategy, SpySerialExtractionService)> strategy() async {
      final exeDir = p.join(base.path, 'pcsx2');
      await Directory(p.join(exeDir, 'memcards')).create(recursive: true);
      final exe = p.join(exeDir, 'pcsx2-qt.exe');
      await File(exe).writeAsString('');
      final ds = await StubDirectoryService.create(exePath: exe);
      final spy = SpySerialExtractionService(ds, await ds.appPrefs());
      return (
        Pcsx2SaveStrategy(ds, await ds.appPrefs(),
            platform: const PlatformInfo('windows', environment: {}), serialExtractionService: spy),
        spy
      );
    }

    test('a multi-disc game reads the launched disc: RomM only knows disc 1', () async {
      final (pcsx2, spy) = await strategy();
      await pcsx2.getSaveFiles(
        Game(
            id: 'm',
            name: 'Two Discs',
            platformSlug: 'ps2',
            fileSize: 0,
            titleId: 'SLUS-11111',
            hasMultipleFiles: true,
            files: const [
              {'file_name': 'Two Discs (Disc 1).chd'},
              {'file_name': 'Two Discs (Disc 2).chd'},
            ]),
        p.join(base.path, 'Two Discs (Disc 2).chd'),
      );
      expect(spy.reads, greaterThan(0));
    });

    test("one disc as .cue + .bin tracks is not multi-disc: RomM's serial is used", () async {
      final (pcsx2, spy) = await strategy();
      await pcsx2.getSaveFiles(
        Game(
            id: 'c',
            name: 'Cue',
            platformSlug: 'ps2',
            fileSize: 0,
            titleId: 'SLUS-22222',
            hasMultipleFiles: true,
            files: const [
              {'file_name': 'Cue.cue'},
              {'file_name': 'Cue (Track 1).bin'},
              {'file_name': 'Cue (Track 2).bin'},
            ]),
        p.join(base.path, 'Cue.cue'),
      );
      expect(spy.reads, 0);
    });

    test('a RomM value that isn\'t a serial is ignored', () async {
      final (pcsx2, spy) = await strategy();
      await pcsx2.getSaveFiles(
          Game(id: 'b', name: 'Bad', platformSlug: 'ps2', fileSize: 0, titleId: '../../evil'), p.join(base.path, 'Bad.iso'));
      expect(spy.reads, greaterThan(0));
    });
  });

  group('RomM serial and the disc that is launched', () {
    Future<(Pcsx2SaveStrategy, SpySerialExtractionService)> strategy() async {
      final exeDir = p.join(base.path, 'pcsx2');
      await Directory(p.join(exeDir, 'memcards')).create(recursive: true);
      final exe = p.join(exeDir, 'pcsx2-qt.exe');
      await File(exe).writeAsString('');
      final ds = await StubDirectoryService.create(exePath: exe);
      final spy = SpySerialExtractionService(ds, await ds.appPrefs());
      return (
        Pcsx2SaveStrategy(ds, await ds.appPrefs(),
            platform: const PlatformInfo('windows', environment: {}), serialExtractionService: spy),
        spy
      );
    }

    // The library list sends no files, so the launched file's name decides.
    Game listed() => Game(id: 'l', name: 'Two Discs', platformSlug: 'ps2', fileSize: 0, titleId: 'SLUS-11111');

    test('disc 2 from the library list (no files known) reads that disc', () async {
      final (pcsx2, spy) = await strategy();
      await pcsx2.getSaveFiles(listed(), p.join(base.path, 'Two Discs (USA) (Disc 2).chd'));
      expect(spy.reads, greaterThan(0));
    });

    test('disc 1 uses RomM\'s serial', () async {
      final (pcsx2, spy) = await strategy();
      await pcsx2.getSaveFiles(listed(), p.join(base.path, 'Two Discs (USA) (Disc 1).chd'));
      expect(spy.reads, 0);
    });

    test('an .m3u playlist uses RomM\'s serial (RomM identifies it by its first disc)', () async {
      final (pcsx2, spy) = await strategy();
      await pcsx2.getSaveFiles(
        Game(
            id: 'm3u',
            name: 'Two Discs',
            platformSlug: 'ps2',
            fileSize: 0,
            titleId: 'SLUS-11111',
            hasMultipleFiles: true,
            files: const [
              {'file_name': 'Two Discs.m3u'},
              {'file_name': 'Two Discs (Disc 1).chd'},
              {'file_name': 'Two Discs (Disc 2).chd'},
            ]),
        p.join(base.path, 'Two Discs.m3u'),
      );
      expect(spy.reads, 0);
    });
  });
}
