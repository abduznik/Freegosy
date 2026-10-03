import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/formats/ps2_memory_card.dart';
import 'package:freegosy/core/save/save_strategy.dart';
import 'package:freegosy/core/save/strategies/ps2_save_folders.dart';
import 'package:freegosy/core/save/strategies/retroarch_save_strategy.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;

import 'save_sync_regression_test.mocks.dart';

/// RetroArch's PS2 core, LRPS2, keeps every game's saves on shared memory
/// cards in the system folder. A game's saves go to RomM as its save folders
/// and come back onto the card without touching the other games' saves.
void main() {
  Uint8List pattern(int seed, int length) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) (seed + i * 7) & 0xFF]);

  Ps2CardSave save(String name, Map<String, Uint8List> files) =>
      Ps2CardSave(name: name, files: [for (final e in files.entries) Ps2CardFile(name: e.key, data: e.value)]);

  final ac5 = save('BASLUS-20851AC5', {'BASLUS-20851AC5': pattern(1, 40000), 'icon.sys': pattern(2, 964)});
  final gt4 = save('BESCES-52438GAMEDATA', {'BESCES-52438GAMEDATA': pattern(3, 124880), 'icon.sys': pattern(4, 964)});
  final ratchet = save('BASCUS-97199RATCHET', {'BASCUS-97199RATCHET': pattern(5, 300000)});

  Uint8List card(List<Ps2CardSave> saves) =>
      Ps2MemoryCard.parse(Ps2MemoryCard.formatted(now: DateTime.utc(2026))).withSaves(saves, (_) => false);

  Map<String, List<int>> filesOf(Ps2CardSave s) => {for (final f in s.files) f.name: f.data.toList()};
  Map<String, Map<String, List<int>>> cardContents(File f) =>
      {for (final s in Ps2MemoryCard.parse(f.readAsBytesSync()).saves) s.name: filesOf(s)};

  /// A zip as Freegosy's push builds one from save folders.
  Uint8List zipOf(Map<String, List<int>> entries) {
    final a = Archive()..addFile(ArchiveFile('freegosy_sync.txt', 2, [123, 125]));
    for (final e in entries.entries) {
      a.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(a));
  }

  late Directory tempDir;
  late String raDir;
  late String memcards;
  late RetroArchSaveStrategy strategy;
  String? serial;

  final game = Game(id: '77', name: 'Ace Combat 5', fsName: 'Ace Combat 5 (USA).chd', platformSlug: 'ps2', fileSize: 0);
  late String romPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ra_lrps2_');
    raDir = p.join(tempDir.path, 'RetroArch');
    memcards = p.join(raDir, 'system', 'pcsx2', 'memcards');
    await Directory(memcards).create(recursive: true);
    await Directory(p.join(raDir, 'saves')).create(recursive: true);
    await File(p.join(raDir, 'retroarch.cfg')).writeAsString([
      'savefile_directory = "${p.join(raDir, 'saves')}"',
      'system_directory = ":\\system"',
      'sort_savefiles_enable = "true"',
    ].join('\n'));
    romPath = p.join(tempDir.path, 'roms', 'ps2', 'Ace Combat 5 (USA).chd');
    serial = 'SLUS-20851';

    final dirService = MockDirectoryService();
    when(dirService.findEmulatorExecutable(argThat(isA<String>()), argThat(isA<String>())))
        .thenAnswer((_) async => null);
    when(dirService.linuxSyncPreset).thenReturn('default');
    strategy = RetroArchSaveStrategy(dirService,
        platform: PlatformInfo('windows', environment: {'APPDATA': tempDir.path, 'USERPROFILE': tempDir.path}))
      ..ps2SerialOverride = ((_) async => serial);
  });

  tearDown(() => tempDir.delete(recursive: true));

  File mcd(int n) => File(p.join(memcards, 'Mcd00$n.ps2'));

  group('push', () {
    test('only this game\'s saves leave the shared card, as save folders', () async {
      mcd(1).writeAsBytesSync(card([gt4, ac5, ratchet]));
      final files = await strategy.getSaveFilesWithScreenshots(game, romPath, syncMode: 'saves');
      expect(files.keys.map((f) => p.basename(f.path)), ['BASLUS-20851AC5']);
      final dir = Directory(files.keys.single.path);
      expect({for (final f in dir.listSync().whereType<File>()) p.basename(f.path): f.readAsBytesSync().toList()},
          filesOf(ac5));
    });

    test('saves on the second card are found too', () async {
      mcd(1).writeAsBytesSync(card([gt4]));
      mcd(2).writeAsBytesSync(card([ac5]));
      final files = await strategy.getSaveFilesWithScreenshots(game, romPath, syncMode: 'saves');
      expect(files.keys.map((f) => p.basename(f.path)), ['BASLUS-20851AC5']);
    });

    test('an unformatted card and a game without saves give nothing', () async {
      mcd(1).writeAsBytesSync(card([gt4]));
      mcd(2).writeAsBytesSync(Uint8List(Ps2MemoryCard.sizeWithEcc)..fillRange(0, Ps2MemoryCard.sizeWithEcc, 0xFF));
      expect(await strategy.getSaveFilesWithScreenshots(game, romPath, syncMode: 'saves'), isEmpty);
    });

    test('nothing when no card changed during the session', () async {
      mcd(1).writeAsBytesSync(card([ac5]));
      final later = DateTime.now().add(const Duration(minutes: 5));
      expect(await strategy.getSaveFilesWithScreenshots(game, romPath, syncMode: 'saves', sessionStart: later),
          isEmpty);
    });

    test('local backups keep the whole cards', () async {
      mcd(1).writeAsBytesSync(card([gt4, ac5]));
      mcd(2).writeAsBytesSync(card([]));
      final files = await strategy.getSaveFiles(game, romPath, syncMode: 'saves');
      expect(files.map((f) => p.basename(f.path)), ['Mcd001.ps2', 'Mcd002.ps2']);
    });
  });

  group('pull', () {
    final newAc5 = {'BASLUS-20851AC5/BASLUS-20851AC5': pattern(9, 50000), 'BASLUS-20851AC5/icon.sys': pattern(8, 964)};

    test('this game\'s saves are replaced, every other save stays byte for byte', () async {
      mcd(1).writeAsBytesSync(card([gt4, ac5, ratchet]));
      expect(await strategy.restoreSave(game, romPath, zipOf(newAc5), 'Ace Combat 5 (USA).zip'), isTrue);
      final after = cardContents(mcd(1));
      expect(after.keys.toSet(), {'BESCES-52438GAMEDATA', 'BASCUS-97199RATCHET', 'BASLUS-20851AC5'});
      expect(after['BESCES-52438GAMEDATA'], filesOf(gt4));
      expect(after['BASCUS-97199RATCHET'], filesOf(ratchet));
      expect(after['BASLUS-20851AC5'], {'BASLUS-20851AC5': pattern(9, 50000).toList(), 'icon.sys': pattern(8, 964).toList()});
      expect(File('${mcd(1).path}.bak').existsSync(), isTrue);
      expect(File('${mcd(1).path}.freegosy_tmp').existsSync(), isFalse);
      expect(Directory(p.join(raDir, 'saves')).listSync(recursive: true), isEmpty,
          reason: 'the save folders go onto the card, not loose into the save folder');
    });

    test('once RetroArch has started without this pull, the card is left as it is', () async {
      mcd(1).writeAsBytesSync(card([gt4, ac5]));
      final before = mcd(1).readAsBytesSync();
      final guard = SaveRestoreGuard()..markTooLate();
      await guard.run(() => strategy.restoreSave(game, romPath, zipOf(newAc5), 'x.zip'));
      expect(mcd(1).readAsBytesSync(), before);
      expect(File('${mcd(1).path}.bak').existsSync(), isFalse);
    });

    test('a missing or never formatted card becomes a formatted card with the save', () async {
      expect(await strategy.restoreSave(game, romPath, zipOf(newAc5), 'x.zip'), isTrue);
      expect(cardContents(mcd(1)).keys, ['BASLUS-20851AC5']);

      mcd(1).writeAsBytesSync(Uint8List(Ps2MemoryCard.sizeWithEcc)..fillRange(0, Ps2MemoryCard.sizeWithEcc, 0xFF));
      expect(await strategy.restoreSave(game, romPath, zipOf(newAc5), 'x.zip'), isTrue);
      expect(cardContents(mcd(1)).keys, ['BASLUS-20851AC5']);
    });

    test('the card that already holds the game\'s saves gets them', () async {
      mcd(1).writeAsBytesSync(card([gt4]));
      mcd(2).writeAsBytesSync(card([ac5]));
      await strategy.restoreSave(game, romPath, zipOf(newAc5), 'x.zip');
      expect(cardContents(mcd(1)).keys, ['BESCES-52438GAMEDATA']);
      expect(cardContents(mcd(2))['BASLUS-20851AC5']!['BASLUS-20851AC5'], pattern(9, 50000).toList());
    });

    test('a PCSX2 folder card upload: only this game\'s folders, without PCSX2\'s bookkeeping', () async {
      mcd(1).writeAsBytesSync(card([gt4]));
      final upload = zipOf({
        'Mcd001.ps2/_pcsx2_superblock': Uint8List(8192),
        'Mcd001.ps2/BASLUS-20851AC5/_pcsx2_index': [1, 2, 3],
        'Mcd001.ps2/BASLUS-20851AC5/BASLUS-20851AC5': pattern(9, 50000),
        'Mcd001.ps2/BASLUS-20502/data': pattern(1, 10),
      });
      await strategy.restoreSave(game, romPath, upload, 'x.zip');
      final after = cardContents(mcd(1));
      expect(after.keys.toSet(), {'BESCES-52438GAMEDATA', 'BASLUS-20851AC5'});
      expect(after['BASLUS-20851AC5']!.keys, ['BASLUS-20851AC5']);
    });

    test('an Argosy upload rooted at the card folder, whatever its name', () async {
      final upload = zipOf({
        'Shared.ps2/_pcsx2_superblock': Uint8List(8192),
        'Shared.ps2/BASLUS-20851AC5/BASLUS-20851AC5': pattern(9, 50000),
      });
      await strategy.restoreSave(game, romPath, upload, 'x.zip');
      expect(cardContents(mcd(1)).keys, ['BASLUS-20851AC5']);
    });

    test('a local backup of the shared cards puts back only this game\'s saves', () async {
      // Backups keep the whole cards (see push).
      final olderAc5 = save('BASLUS-20851AC5', {'BASLUS-20851AC5': pattern(11, 40000)});
      final one = card([olderAc5, gt4]), two = card([]);
      final backup = Uint8List.fromList(ZipEncoder().encode(Archive()
        ..addFile(ArchiveFile('Mcd001.ps2', one.length, one))
        ..addFile(ArchiveFile('Mcd002.ps2', two.length, two))));
      final newerGt4 = save('BESCES-52438GAMEDATA', {'BESCES-52438GAMEDATA': pattern(12, 124880)});
      mcd(1).writeAsBytesSync(card([ac5, newerGt4]));

      expect(await strategy.restoreBackup(game, romPath, backup, 'freegosy_77_backup.zip'), isTrue);
      final after = cardContents(mcd(1));
      expect(after['BASLUS-20851AC5'], filesOf(olderAc5), reason: 'this game: back to the backup');
      expect(after['BESCES-52438GAMEDATA'], filesOf(newerGt4), reason: 'another game: untouched');
    });

    test('a whole PCSX2 file card upload: only this game\'s saves are taken', () async {
      mcd(1).writeAsBytesSync(card([ratchet]));
      await strategy.restoreSave(game, romPath, card([gt4, ac5]), 'Mcd001.ps2');
      expect(cardContents(mcd(1)).keys.toSet(), {'BASCUS-97199RATCHET', 'BASLUS-20851AC5'});
    });

    test('an upload without this game\'s saves leaves the cards alone', () async {
      mcd(1).writeAsBytesSync(card([gt4]));
      final before = mcd(1).readAsBytesSync();
      await strategy.restoreSave(game, romPath, zipOf({'BASLUS-20502/data': pattern(1, 10)}), 'x.zip');
      expect(mcd(1).readAsBytesSync(), before);
      expect(File('${mcd(1).path}.bak').existsSync(), isFalse);
    });

    test('a save that does not fit is refused and the card is not changed', () async {
      // 8,104 of the card's 8,135 KB used; the new save needs 52 more.
      mcd(1).writeAsBytesSync(card([save('BASLUS-99999BIG', {'big': Uint8List(8100 * 1024)})]));
      final before = mcd(1).readAsBytesSync();
      await expectLater(strategy.restoreSave(game, romPath, zipOf(newAc5), 'x.zip'),
          throwsA(isA<SaveSyncNotPossibleException>()));
      expect(mcd(1).readAsBytesSync(), before);
    });

    test('a local card that can\'t be read is left alone', () async {
      final damaged = card([gt4]);
      damaged[0x34] = 0xFF; // the allocatable area now starts past the end
      mcd(1).writeAsBytesSync(damaged);
      await expectLater(strategy.restoreSave(game, romPath, zipOf(newAc5), 'x.zip'),
          throwsA(isA<SaveSyncNotPossibleException>()));
      expect(mcd(1).readAsBytesSync(), damaged);
    });
  });

  group('serial unknown', () {
    setUp(() => serial = null);

    test('shared cards: nothing is synced, and the user is told why', () async {
      mcd(1).writeAsBytesSync(card([gt4, ac5]));
      expect(await strategy.getSaveFilesWithScreenshots(game, romPath, syncMode: 'saves'), isEmpty);
      expect(await strategy.saveSyncBlockedReason(game, romPath), contains('serial'));
      final before = mcd(1).readAsBytesSync();
      await expectLater(strategy.restoreSave(game, romPath, card([ac5]), 'Mcd001.ps2'),
          throwsA(isA<SaveSyncNotPossibleException>()));
      expect(mcd(1).readAsBytesSync(), before);
    });
  });

  group('per-game cards (Shared Memory Cards off)', () {
    late File own;
    setUp(() async {
      final opts = Directory(p.join(raDir, 'config', 'LRPS2'))..createSync(recursive: true);
      File(p.join(opts.path, 'LRPS2.opt')).writeAsStringSync('pcsx2_shared_memory_cards = "disabled"\n');
      own = File(p.join(raDir, 'saves', 'LRPS2', 'Ace Combat 5 (USA).ps2'));
    });

    test('the game\'s own card in the save folder is used', () async {
      await own.parent.create(recursive: true);
      own.writeAsBytesSync(card([ac5]));
      mcd(1).writeAsBytesSync(card([gt4]));
      final files = await strategy.getSaveFilesWithScreenshots(game, romPath, syncMode: 'saves');
      expect(files.keys.map((f) => p.basename(f.path)), ['BASLUS-20851AC5']);
      expect(await strategy.pullMustFinishBeforeLaunch(game, romPath), isFalse);

      await strategy.restoreSave(game, romPath, zipOf({'BASLUS-20851AC5/x': pattern(1, 5)}), 'x.zip');
      expect(cardContents(own)['BASLUS-20851AC5']!.keys, ['x']);
      expect(cardContents(mcd(1)).keys, ['BESCES-52438GAMEDATA']);
    });

    test('without a serial every save on the game\'s own card is its own', () async {
      serial = null;
      await own.parent.create(recursive: true);
      own.writeAsBytesSync(card([ac5]));
      expect(await strategy.saveSyncBlockedReason(game, romPath), isNull);
      final files = await strategy.getSaveFilesWithScreenshots(game, romPath, syncMode: 'saves');
      expect(files.keys.map((f) => p.basename(f.path)), ['BASLUS-20851AC5']);
    });

    test('a game-specific option file wins over the core\'s', () async {
      File(p.join(raDir, 'config', 'LRPS2', 'Ace Combat 5 (USA).opt'))
          .writeAsStringSync('pcsx2_shared_memory_cards = "enabled"\n');
      expect(await strategy.pullMustFinishBeforeLaunch(game, romPath), isTrue);
    });
  });

  test('shared cards: the pull finishes before LRPS2 starts', () async {
    expect(await strategy.pullMustFinishBeforeLaunch(game, romPath), isTrue);
  });

  test('other RetroArch platforms are not affected', () async {
    final snes = Game(id: '1', name: 'Zelda', fsName: 'Zelda.sfc', platformSlug: 'snes', fileSize: 0);
    expect(await strategy.pullMustFinishBeforeLaunch(snes, 'Zelda.sfc'), isFalse);
    expect(await strategy.saveSyncBlockedReason(snes, 'Zelda.sfc'), isNull);
  });

  test('a push restored on another PC gives the same saves', () async {
    mcd(1).writeAsBytesSync(card([gt4, ac5]));
    final folders = (await strategy.getSaveFilesWithScreenshots(game, romPath, syncMode: 'saves')).keys;
    final entries = <String, List<int>>{
      for (final dir in folders)
        for (final f in Directory(dir.path).listSync().whereType<File>())
          '${p.basename(dir.path)}/${p.basename(f.path)}': f.readAsBytesSync(),
    };
    // The other PC: a card with only Ratchet on it.
    mcd(1).writeAsBytesSync(card([ratchet]));
    await strategy.restoreSave(game, romPath, zipOf(entries), 'x.zip');
    final after = cardContents(mcd(1));
    expect(after.keys.toSet(), {'BASCUS-97199RATCHET', 'BASLUS-20851AC5'});
    expect(after['BASLUS-20851AC5'], filesOf(ac5));
  });

  group('Ps2SaveFolders', () {
    test('lrps2UsesSharedCards: the first file that sets it wins; shared by default', () {
      expect(Ps2SaveFolders.lrps2UsesSharedCards([]), isTrue);
      expect(Ps2SaveFolders.lrps2UsesSharedCards(['x = "1"\npcsx2_shared_memory_cards = "disabled"']), isFalse);
      expect(
          Ps2SaveFolders.lrps2UsesSharedCards(
              ['pcsx2_shared_memory_cards = "enabled"', 'pcsx2_shared_memory_cards = "disabled"']),
          isTrue);
    });

    test('isSaveOf matches the serial after the region prefix', () {
      expect(Ps2SaveFolders.isSaveOf('BASLUS-20851AC5', 'SLUS-20851'), isTrue);
      expect(Ps2SaveFolders.isSaveOf('BESCES-52438GAMEDATA', 'SCES-52438'), isTrue);
      expect(Ps2SaveFolders.isSaveOf('BASLUS-20852AC5', 'SLUS-20851'), isFalse);
      expect(Ps2SaveFolders.isSaveOf('BASLUS', 'SLUS-20851'), isFalse);
      expect(Ps2SaveFolders.isSaveOf('baslus_20851ac5', 'slus-20851'), isTrue);
    });

    test('savesFromUpload skips states, loose files and nested folders', () {
      final saves = Ps2SaveFolders.savesFromUpload(
          zipOf({
            'Ace Combat 5 (USA).state1': [1],
            'loose.bin': [1],
            'BASLUS-20851AC5/a': [1],
            'BASLUS-20851AC5/sub/b': [1],
            'NOTASAVE/c': [1],
          }),
          'x.zip');
      expect(saves.map((s) => s.name), ['BASLUS-20851AC5']);
      expect(saves.single.files.map((f) => f.name), ['a']);
    });
  });
}
