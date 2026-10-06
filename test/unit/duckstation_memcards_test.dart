import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/formats/ps1_memory_card.dart';
import 'package:freegosy/core/save/save_strategy.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/save/strategies/duckstation_config.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/duckstation_test_env.dart';
import '../helpers/ps1_card_builder.dart';
import 'save_sync_service_test.mocks.dart';

void main() {
  late Directory base;
  late DuckstationTestEnv env;
  final game = Game(
      id: 'g1',
      name: 'Colin McRae Rally 2.0',
      fsName: 'Colin McRae Rally 2.0 (Europe) (SLES-02605).chd',
      platformSlug: 'psx',
      fileSize: 0);
  const saveName = 'Colin McRae Rally 2.0 (Europe) (En,Fr,De,Es,It)';
  const gamedb = 'SLES-02605:\n  name: "Colin McRae Rally 2.0"\n  saveName: "$saveName"\n';

  setUp(() async {
    DuckstationGameDb.clearCache();
    base = await Directory.systemTemp.createTemp('duckstation_memcards');
    env = await DuckstationTestEnv.create(base);
  });

  tearDown(() => base.delete(recursive: true));

  String romPath() => p.join(base.path, 'Colin McRae Rally 2.0 (Europe) (SLES-02605).chd');

  /// The name a port-1 card is uploaded under: the ROM name as a RetroArch
  /// `.srm` (the same card format; see docs/save-interop.md).
  const srmName = 'Colin McRae Rally 2.0 (Europe) (SLES-02605).srm';
  Future<void> cardTypes(String types) => env.writeSettings('[MemoryCards]\n$types\n');
  Future<List<String>> saveFiles() async =>
      (await env.strategy.getSaveFiles(game, romPath())).map((f) => p.basename(f.path)).toList();
  /// The memory cards on disk (not the .bak copies made before overwriting).
  List<String> cardsOnDisk() => Directory(env.memcardsDir)
      .listSync()
      .map((e) => p.basename(e.path))
      .where((name) => name.endsWith('.mcd'))
      .toList()
    ..sort();

  Uint8List zip(Map<String, List<int>> entries) {
    final archive = Archive();
    for (final e in entries.entries) {
      archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  group('which cards are uploaded', () {
    setUp(() async {
      await env.writeCard('SLES-02605_1.mcd');
      await env.writeCard('Colin McRae Rally 2.0 (Europe) (SLES-02605)_1.mcd');
      await env.writeCard('${saveName}_1.mcd');
      await env.writeCard('shared_card_1.mcd');
      await env.writeCard('Another Game_1.mcd');
    });

    test('by serial: <serial>_1.mcd only', () async {
      await cardTypes('Card1Type = PerGame');
      expect(await saveFiles(), ['SLES-02605_1.mcd']);
    });

    test('by file title: <ROM file name>_1.mcd only', () async {
      await cardTypes('Card1Type = PerGameFileTitle');
      expect(await saveFiles(), ['Colin McRae Rally 2.0 (Europe) (SLES-02605)_1.mcd']);
    });

    test('by title: the saveName from DuckStation\'s own game database', () async {
      await cardTypes('Card1Type = PerGameTitle');
      await env.writeGameDb(gamedb);
      expect(await saveFiles(), ['${saveName}_1.mcd']);
    });

    group('by title, a multi-disc game', () {
      const discsets = '- name: "Colin Set"\n  saveName: "Colin Set Save"\n  serials:\n    - SLES-02605\n    - SLES-12605\n';
      const discCard = '${saveName}_1.mcd';
      setUp(() async {
        await cardTypes('Card1Type = PerGameTitle');
        await env.writeGameDb(gamedb, discsets: discsets);
        await File(p.join(env.memcardsDir, discCard)).delete(); // the group's setUp made one
      });

      test('the disc set\'s card', () async {
        await env.writeCard('Colin Set Save_1.mcd');
        expect(await saveFiles(), ['Colin Set Save_1.mcd']);
      });

      test('a card already made under the disc\'s own title wins, as in DuckStation', () async {
        await env.writeCard('Colin Set Save_1.mcd');
        await env.writeCard(discCard);
        expect(await saveFiles(), [discCard]);
      });

      test('the disc\'s own card with playlist titles off', () async {
        await cardTypes('Card1Type = PerGameTitle\nUsePlaylistTitle = false');
        await env.writeCard('Colin Set Save_1.mcd');
        await env.writeCard(discCard);
        expect(await saveFiles(), [discCard]);
      });

      test('a pull writes the disc set\'s card when the disc has none of its own', () async {
        final ok = await env.strategy.restoreSave(game, romPath(), buildPs1Card([]), 'SLES-02605_1.mcd');
        expect(ok, isTrue);
        expect(cardsOnDisk(), contains('Colin Set Save_1.mcd'));
        expect(cardsOnDisk(), isNot(contains(discCard)));
      });
    });

    test('by title with no game database: an existing card matched by name', () async {
      await cardTypes('Card1Type = PerGameTitle');
      final files = await saveFiles();
      expect(files, hasLength(1));
      expect(files.single, isNot('shared_card_1.mcd'));
      expect(files.single, contains('Colin McRae Rally 2.0'));
    });

    test('both ports per game: both cards', () async {
      await cardTypes('Card1Type = PerGame\nCard2Type = PerGame');
      await env.writeCard('SLES-02605_2.mcd');
      expect(await saveFiles(), ['SLES-02605_1.mcd', 'SLES-02605_2.mcd']);
    });

    test('local backups keep the whole shared card next to the per-game one', () async {
      await cardTypes('Card1Type = PerGame\nCard2Type = Shared');
      await env.writeCard('shared_card_2.mcd');
      expect(await saveFiles(), ['SLES-02605_1.mcd', 'shared_card_2.mcd']);
    });

    test('only shared: local backups keep the whole shared card', () async {
      await cardTypes('Card1Type = Shared');
      expect(await saveFiles(), ['shared_card_1.mcd']);
    });

    test('the game\'s own settings win over the global ones', () async {
      await cardTypes('Card1Type = Shared');
      await env.writeGameSettings('SLES-02605', '[MemoryCards]\nCard1Type = PerGame\n');
      expect(await saveFiles(), ['SLES-02605_1.mcd']);
    });

    group('as uploaded', () {
      Future<List<File>> uploads() async =>
          (await env.strategy.getSaveFilesWithScreenshots(game, romPath())).keys.toList();

      test('the port-1 card goes up as <ROM name>.srm, the same bytes, outside DuckStation\'s folder',
          () async {
        await cardTypes('Card1Type = PerGame');

        final file = (await uploads()).single;

        expect(p.basename(file.path), srmName);
        expect(p.isWithin(env.memcardsDir, file.path), isFalse);
        expect(file.readAsBytesSync(), File(p.join(env.memcardsDir, 'SLES-02605_1.mcd')).readAsBytesSync());
      });

      test('a second per-game port keeps its DuckStation name next to the .srm', () async {
        await cardTypes('Card1Type = PerGame\nCard2Type = PerGame');
        await env.writeCard('SLES-02605_2.mcd');

        expect((await uploads()).map((f) => p.basename(f.path)), [srmName, 'SLES-02605_2.mcd']);
      });

      test('local backups keep DuckStation\'s own names', () async {
        await cardTypes('Card1Type = PerGame');
        expect(await saveFiles(), ['SLES-02605_1.mcd']);
      });

      test('uploaded from one PC and restored on another, it lands under that PC\'s name', () async {
        await cardTypes('Card1Type = PerGame');
        final file = (await uploads()).single;
        final bytes = file.readAsBytesSync();
        await cardTypes('Card1Type = PerGameFileTitle');

        await env.strategy.restoreSave(game, romPath(), bytes, p.basename(file.path));

        expect(File(p.join(env.memcardsDir, 'Colin McRae Rally 2.0 (Europe) (SLES-02605)_1.mcd')).readAsBytesSync(),
            bytes);
      });
    });

    test('the memory card folder follows the Directory setting', () async {
      final elsewhere = Directory(p.join(base.path, 'elsewhere'))..createSync();
      File(p.join(elsewhere.path, 'SLES-02605_1.mcd')).writeAsBytesSync(List.filled(64, 1));
      await cardTypes('Card1Type = PerGame\nDirectory = ${elsewhere.path}');

      final files = await env.strategy.getSaveFiles(game, romPath());

      expect(files.single.path, p.join(elsewhere.path, 'SLES-02605_1.mcd'));
      expect(await env.strategy.getSaveDir(game, romPath()), elsewhere.path);
    });
  });

  group('restoring under this PC\'s names', () {
    test('a card made by serial is written under the title this PC uses', () async {
      await env.writeGameDb(gamedb); // default settings: by title
      final ok = await env.strategy
          .restoreSave(game, romPath(), Uint8List.fromList(List.filled(64, 7)), 'SLES-02605_1.mcd');

      expect(ok, isTrue);
      expect(cardsOnDisk(), ['${saveName}_1.mcd']);
      expect(File(p.join(env.memcardsDir, '${saveName}_1.mcd')).readAsBytesSync().first, 7);
    });

    test('a card made by title is written by file title, keeping its port', () async {
      await cardTypes('Card1Type = PerGameFileTitle\nCard2Type = PerGameFileTitle');
      final bundle = zip({'${saveName}_1.mcd': List.filled(64, 1), '${saveName}_2.mcd': List.filled(64, 2)});

      await env.strategy.restoreSave(game, romPath(), bundle, 'Colin.zip');

      expect(cardsOnDisk(), [
        'Colin McRae Rally 2.0 (Europe) (SLES-02605)_1.mcd',
        'Colin McRae Rally 2.0 (Europe) (SLES-02605)_2.mcd',
      ]);
    });

    test('a card for a port that has no per-game card here is skipped', () async {
      await cardTypes('Card1Type = PerGame\nCard2Type = None');
      final bundle = zip({'SLES-02605_1.mcd': List.filled(64, 1), 'SLES-02605_2.mcd': List.filled(64, 2)});

      await env.strategy.restoreSave(game, romPath(), bundle, 'Colin.zip');

      expect(cardsOnDisk(), ['SLES-02605_1.mcd']);
    });

    test('an old upload of a shared card loses to the game\'s own card in the same bundle', () async {
      await cardTypes('Card1Type = PerGame');
      final bundle = zip({'SLES-02605_1.mcd': List.filled(64, 9), 'shared_card_1.mcd': List.filled(64, 3)});

      await env.strategy.restoreSave(game, romPath(), bundle, 'Colin.zip');

      expect(cardsOnDisk(), ['SLES-02605_1.mcd']);
      expect(File(p.join(env.memcardsDir, 'SLES-02605_1.mcd')).readAsBytesSync().first, 9);
    });

    test('by title with no game database and no card yet: named after the ROM without tags', () async {
      await env.strategy
          .restoreSave(game, romPath(), Uint8List.fromList(List.filled(64, 1)), 'SLES-02605_1.mcd');

      expect(cardsOnDisk(), ['Colin McRae Rally 2.0_1.mcd']);
    });

    test('by title with no game database: an existing card is updated in place', () async {
      await env.writeCard('Colin McRae Rally 2.0 (Europe)_1.mcd', fill: 1);

      await env.strategy
          .restoreSave(game, romPath(), Uint8List.fromList(List.filled(64, 5)), 'SLES-02605_1.mcd');

      expect(cardsOnDisk(), ['Colin McRae Rally 2.0 (Europe)_1.mcd']);
      expect(File(p.join(env.memcardsDir, 'Colin McRae Rally 2.0 (Europe)_1.mcd')).readAsBytesSync().first, 5);
    });

    test('by serial when the serial can\'t be read: nothing is written', () async {
      await cardTypes('Card1Type = PerGame');
      final unknown = Game(id: 'g2', name: 'No Serial', platformSlug: 'psx', fileSize: 0);

      final ok = await env.strategy.restoreSave(unknown, p.join(base.path, 'No Serial.iso'),
          Uint8List.fromList(List.filled(64, 1)), 'SLES-02605_1.mcd');

      expect(ok, isTrue);
      expect(Directory(env.memcardsDir).listSync(), isEmpty);
    });
  });

  group('when sync is not possible', () {
    test('one shared card: not blocked, the game\'s saves are synced out of it', () async {
      await cardTypes('Card1Type = Shared');
      expect(await env.strategy.saveSyncBlockedReason(game, romPath()), isNull);
    });

    test('no card or a non-persistent one: blocked, nothing to sync', () async {
      await cardTypes('Card1Type = NonPersistent');
      expect(await env.strategy.saveSyncBlockedReason(game, romPath()), contains('nothing to sync'));
      await cardTypes('Card1Type = None');
      expect(await env.strategy.saveSyncBlockedReason(game, romPath()), contains('nothing to sync'));
    });

    test('any per-game port: not blocked (default settings included)', () async {
      expect(await env.strategy.saveSyncBlockedReason(game, romPath()), isNull);
      await cardTypes('Card1Type = Shared\nCard2Type = PerGame');
      expect(await env.strategy.saveSyncBlockedReason(game, romPath()), isNull);
    });

    test('a per-game override lifts a global non-persistent card', () async {
      await cardTypes('Card1Type = NonPersistent');
      await env.writeGameSettings('SLES-02605', '[MemoryCards]\nCard1Type = PerGameTitle\n');
      expect(await env.strategy.saveSyncBlockedReason(game, romPath()), isNull);
    });

    test('SaveSyncService push and pull stop before contacting RomM', () async {
      await cardTypes('Card1Type = NonPersistent');
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final romm = MockRommService();
      final sync = SaveSyncService(romm, env.directoryService, StrategyRegistry(env.directoryService, prefs), prefs);

      await expectLater(sync.pushSaves(game, romPath(), emulatorId: 'duckstation'),
          throwsA(isA<SaveSyncNotPossibleException>()));
      await expectLater(sync.pullSave(game, romPath(), emulatorId: 'duckstation'),
          throwsA(isA<SaveSyncNotPossibleException>()));
      verifyNever(romm.fetchCapabilities());
    });
  });

  group('a card shared by all games', () {
    final colinSetting = (name: 'BESLES-02605-SETTING', blocks: [3], fill: 0x11);
    final colinGame = (name: 'BESLES-02605GAME01', blocks: [5, 6], fill: 0x22);
    final otherGame = (name: 'BASLUS-00594GAME', blocks: [1, 2], fill: 0x33);
    bool colin(String name) => name.substring(2, 12) == 'SLES-02605';

    setUp(() => cardTypes('Card1Type = Shared'));

    Future<File> writeShared(List<TestSave> saves, {String name = 'shared_card_1.mcd'}) async {
      final file = File(p.join(env.memcardsDir, name));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(buildPs1Card(saves));
      return file;
    }

    Future<List<File>> syncFiles({DateTime? sessionStart}) async =>
        (await env.strategy.getSaveFilesWithScreenshots(game, romPath(), sessionStart: sessionStart))
            .keys
            .toList();

    group('push', () {
      test('uploads a card holding only this game\'s saves, named like a RetroArch card', () async {
        final shared = await writeShared([otherGame, colinSetting, colinGame]);

        final file = (await syncFiles()).single;

        expect(p.basename(file.path), srmName);
        expect(p.isWithin(env.memcardsDir, file.path), isFalse, reason: 'a temporary copy, not a card of DuckStation\'s');
        final card = Ps1MemoryCard.parse(file.readAsBytesSync());
        expect(card.saves.map((s) => s.name), [colinSetting.name, colinGame.name]);
        expect(file.readAsBytesSync(), Ps1MemoryCard.parse(shared.readAsBytesSync()).extract(colin));
      });

      test('the shared card\'s own CardNPath is honoured', () async {
        await cardTypes('Card1Type = Shared\nCard1Path = my_card.mcd');
        await writeShared([colinSetting], name: 'my_card.mcd');

        expect((await syncFiles()).map((f) => p.basename(f.path)), [srmName]);
      });

      test('nothing when the game has no saves on the card, or the card is missing or damaged', () async {
        expect(await syncFiles(), isEmpty, reason: 'no card');
        await writeShared([otherGame]);
        expect(await syncFiles(), isEmpty, reason: 'no saves of this game');
        await File(p.join(env.memcardsDir, 'shared_card_1.mcd')).writeAsBytes(List.filled(1000, 1));
        expect(await syncFiles(), isEmpty, reason: 'not a memory card');
      });

      test('nothing when the card was not written during the session', () async {
        final shared = await writeShared([colinSetting]);
        await shared.setLastModified(DateTime(2026, 1, 1));

        expect(await syncFiles(sessionStart: DateTime(2026, 6, 1)), isEmpty);
        expect(await syncFiles(sessionStart: DateTime(2025, 6, 1)), hasLength(1));
      });

      test('nothing when the serial can\'t be read', () async {
        await writeShared([colinSetting]);
        final unknown = Game(id: 'g2', name: 'No Serial', platformSlug: 'psx', fileSize: 0);

        final files = await env.strategy.getSaveFilesWithScreenshots(unknown, p.join(base.path, 'No Serial.iso'));

        expect(files, isEmpty);
      });

      test('a multi-disc game takes the saves of all its discs', () async {
        await env.writeGameDb('', discsets: '- name: "Two Discs"\n  serials:\n    - SLES-02605\n    - SLES-12605\n');
        await writeShared([colinSetting, (name: 'BESLES-12605DISC2', blocks: [9], fill: 0x44), otherGame]);

        final card = Ps1MemoryCard.parse((await syncFiles()).single.readAsBytesSync());

        expect(card.saves.map((s) => s.name), [colinSetting.name, 'BESLES-12605DISC2']);
      });

      test('local backups still get the whole card', () async {
        await writeShared([otherGame, colinSetting]);
        expect(await saveFiles(), ['shared_card_1.mcd']);
      });
    });

    group('pull', () {
      test('replaces this game\'s saves on the card and leaves the other games\' bytes alone', () async {
        final shared = await writeShared([otherGame, colinSetting]);
        final before = shared.readAsBytesSync();
        final incoming = buildPs1Card([(name: 'BESLES-02605NEW', blocks: [1, 2], fill: 0x66)]);

        final ok = await env.strategy.restoreSave(game, romPath(), incoming, 'SLES-02605_1.mcd');

        expect(ok, isTrue);
        final after = shared.readAsBytesSync();
        final card = Ps1MemoryCard.parse(after);
        expect(card.saves.map((s) => s.name).toSet(), {otherGame.name, 'BESLES-02605NEW'});
        for (final block in otherGame.blocks) {
          expect(blockData(after, block), blockData(before, block));
        }
        expect(cardsOnDisk(), ['shared_card_1.mcd'], reason: 'no per-game card is written');
        expect(File('${shared.path}.bak').existsSync(), isTrue, reason: 'the old card is backed up first');
      });

      test('a local backup of the shared card puts back only this game\'s saves', () async {
        final newerOther = (name: otherGame.name, blocks: otherGame.blocks, fill: 0x55);
        final shared = await writeShared([newerOther, colinSetting]);
        final before = shared.readAsBytesSync();
        final backedUp = buildPs1Card([otherGame, (name: 'BESLES-02605-OLDER', blocks: [3], fill: 0x77)]);
        final backup = Uint8List.fromList(
            ZipEncoder().encode(Archive()..addFile(ArchiveFile('shared_card_1.mcd', backedUp.length, backedUp))));

        expect(await env.strategy.restoreBackup(game, romPath(), backup, 'freegosy_g1_backup.zip'), isTrue);

        final after = shared.readAsBytesSync();
        expect(Ps1MemoryCard.parse(after).saves.map((s) => s.name).toSet(), {otherGame.name, 'BESLES-02605-OLDER'});
        for (final block in otherGame.blocks) {
          expect(blockData(after, block), blockData(before, block), reason: 'another game: untouched');
        }
      });

      test('once DuckStation has started without this pull, the card is left as it is', () async {
        final shared = await writeShared([otherGame, colinSetting]);
        final before = shared.readAsBytesSync();
        final incoming = buildPs1Card([(name: 'BESLES-02605NEW', blocks: [1, 2], fill: 0x66)]);

        final guard = SaveRestoreGuard()..markTooLate();
        await guard.run(() => env.strategy.restoreSave(game, romPath(), incoming, 'SLES-02605_1.mcd'));

        expect(shared.readAsBytesSync(), before);
        expect(File('${shared.path}.bak').existsSync(), isFalse);

        await SaveRestoreGuard().run(() => env.strategy.restoreSave(game, romPath(), incoming, 'SLES-02605_1.mcd'));
        expect(Ps1MemoryCard.parse(shared.readAsBytesSync()).saves.map((s) => s.name).toSet(),
            {otherGame.name, 'BESLES-02605NEW'},
            reason: 'a pull in time is written as before');
      });

      test('creates the shared card when there is none yet', () async {
        final incoming = buildPs1Card([colinSetting]);

        await env.strategy.restoreSave(game, romPath(), incoming, 'SLES-02605_1.mcd');

        final card = Ps1MemoryCard.parse(File(p.join(env.memcardsDir, 'shared_card_1.mcd')).readAsBytesSync());
        expect(card.saves.map((s) => s.name), [colinSetting.name]);
      });

      test('an incoming card with none of this game\'s saves changes nothing', () async {
        final shared = await writeShared([otherGame, colinSetting]);
        final before = shared.readAsBytesSync();

        await env.strategy.restoreSave(game, romPath(), buildPs1Card([otherGame]), 'SLES-02605_1.mcd');

        expect(shared.readAsBytesSync(), before);
      });

      test('a full card: nothing is written, and the user is told why', () async {
        final shared = await writeShared([
          (name: 'BASLUS-00594BIG', blocks: List.generate(14, (i) => i + 1), fill: 3),
        ]);
        final before = shared.readAsBytesSync();
        final incoming = buildPs1Card([(name: 'BESLES-02605NEW', blocks: [1, 2], fill: 0x66)]);

        await expectLater(
          env.strategy.restoreSave(game, romPath(), incoming, 'SLES-02605_1.mcd'),
          throwsA(isA<SaveSyncNotPossibleException>()
              .having((e) => e.message, 'message', allOf(contains('2 blocks'), contains('1 free')))),
        );
        expect(shared.readAsBytesSync(), before);
      });

      test('a damaged shared card or incoming card: nothing is written, and the user is told why', () async {
        final shared = File(p.join(env.memcardsDir, 'shared_card_1.mcd'))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(List.filled(128 * 1024, 0));
        await expectLater(
          env.strategy.restoreSave(game, romPath(), buildPs1Card([colinSetting]), 'SLES-02605_1.mcd'),
          throwsA(isA<SaveSyncNotPossibleException>()),
        );
        expect(shared.readAsBytesSync(), everyElement(0));

        await writeShared([otherGame]);
        await expectLater(
          env.strategy.restoreSave(game, romPath(), Uint8List(500), 'SLES-02605_1.mcd'),
          throwsA(isA<SaveSyncNotPossibleException>()),
        );
      });

      test('pushed from one PC and pulled on another, the saves arrive unchanged', () async {
        await writeShared([otherGame, colinSetting, colinGame]);
        final uploadedFile = (await syncFiles()).single;
        final uploaded = uploadedFile.readAsBytesSync();

        // The other PC: a shared card with a different game and an older save.
        await writeShared([(name: 'BASCUS-94163FF7', blocks: [4], fill: 0x77), (name: 'BESLES-02605OLD', blocks: [8], fill: 1)]);
        await env.strategy.restoreSave(game, romPath(), uploaded, p.basename(uploadedFile.path));

        final pushedBack = (await syncFiles()).single.readAsBytesSync();
        expect(pushedBack, uploaded, reason: 'same saves, same bytes: no needless re-upload');
      });
    });

    test('a per-game PC restoring an old upload of a whole shared card keeps only this game\'s saves', () async {
      await cardTypes('Card1Type = PerGame');
      final oldUpload = buildPs1Card([otherGame, colinSetting]);

      await env.strategy.restoreSave(game, romPath(), oldUpload, 'shared_card_1.mcd');

      final card = Ps1MemoryCard.parse(File(p.join(env.memcardsDir, 'SLES-02605_1.mcd')).readAsBytesSync());
      expect(card.saves.map((s) => s.name), [colinSetting.name]);
    });

    group('a card uploaded by Argosy (RetroArch keeps it as <ROM name>.srm)', () {
      const argosyName = 'Colin McRae Rally 2.0 (Europe) (En,Fr,De,Es,It).srm';

      test('becomes this game\'s own card on a per-game PC', () async {
        await cardTypes('Card1Type = PerGame');

        final ok = await env.strategy.restoreSave(game, romPath(), buildPs1Card([colinSetting]), argosyName);

        expect(ok, isTrue);
        expect(cardsOnDisk(), ['SLES-02605_1.mcd']);
        final card = Ps1MemoryCard.parse(File(p.join(env.memcardsDir, 'SLES-02605_1.mcd')).readAsBytesSync());
        expect(card.saves.map((s) => s.name), [colinSetting.name]);
      });

      test('is merged into a shared card like any other', () async {
        final shared = await writeShared([otherGame]);

        await env.strategy.restoreSave(game, romPath(), buildPs1Card([colinSetting]), argosyName);

        expect(Ps1MemoryCard.parse(shared.readAsBytesSync()).saves.map((s) => s.name).toSet(),
            {otherGame.name, colinSetting.name});
      });

      test('an .srm that is not a PS1 memory card is ignored', () async {
        await cardTypes('Card1Type = PerGame');

        final wrongSize = await env.strategy
            .restoreSave(game, romPath(), Uint8List.fromList(List.filled(8192, 1)), argosyName);
        final noHeader = await env.strategy
            .restoreSave(game, romPath(), Uint8List(128 * 1024), argosyName);

        expect([wrongSize, noHeader], [true, true]);
        expect(Directory(env.memcardsDir).existsSync() ? cardsOnDisk() : <String>[], isEmpty);
      });
    });

    test('the pull must finish before launch only when a shared card may be patched', () async {
      expect(await env.strategy.pullMustFinishBeforeLaunch(game, romPath()), isTrue);
      await cardTypes('Card1Type = PerGame');
      expect(await env.strategy.pullMustFinishBeforeLaunch(game, romPath()), isFalse);
    });
  });
}
