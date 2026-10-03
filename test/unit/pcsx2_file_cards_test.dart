import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/formats/ps2_memory_card.dart';
import 'package:freegosy/core/save/save_strategy.dart';
import 'package:path/path.dart' as p;

import '../helpers/pcsx2_test_env.dart';

/// PCSX2's default memory card is a file (`memcards/Mcd001.ps2`, an 8 MB
/// image) shared by every game. A game's saves go to RomM as its save
/// folders, as with folder cards, LRPS2 and Argosy, and come back onto the
/// card without touching the other games' saves.
void main() {
  Uint8List pattern(int seed, int length) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) (seed + i * 7) & 0xFF]);

  Ps2CardSave save(String name, Map<String, Uint8List> files) =>
      Ps2CardSave(name: name, files: [for (final e in files.entries) Ps2CardFile(name: e.key, data: e.value)]);

  final ac5 = save('BASLUS-20851AC5', {'BASLUS-20851AC5': pattern(1, 40000), 'icon.sys': pattern(2, 964)});
  final gt4 = save('BESCES-52438GAMEDATA', {'BESCES-52438GAMEDATA': pattern(3, 124880)});
  final ratchet = save('BASCUS-97199RATCHET', {'BASCUS-97199RATCHET': pattern(5, 300000)});

  Uint8List card(List<Ps2CardSave> saves) =>
      Ps2MemoryCard.parse(Ps2MemoryCard.formatted(now: DateTime.utc(2026))).withSaves(saves, (_) => false);

  Map<String, List<int>> filesOf(Ps2CardSave s) => {for (final f in s.files) f.name: f.data.toList()};
  Map<String, Map<String, List<int>>> cardContents(File f) =>
      {for (final s in Ps2MemoryCard.parse(f.readAsBytesSync()).saves) s.name: filesOf(s)};
  Map<String, List<int>> folderContents(Directory d) =>
      {for (final f in d.listSync().whereType<File>()) p.basename(f.path): f.readAsBytesSync().toList()};

  Uint8List zipOf(Map<String, List<int>> entries) {
    final a = Archive()..addFile(ArchiveFile('freegosy_sync.txt', 2, [123, 125]));
    for (final e in entries.entries) {
      a.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(a));
  }

  late Directory tempDir;
  late Pcsx2TestEnv env;
  late String memcards;
  final game = Game(id: '77', name: 'Ace Combat 5', platformSlug: 'ps2', fileSize: 0);
  String romPath([String name = 'Ace Combat 5 (SLUS-20851).iso']) => p.join(tempDir.path, 'roms', name);
  File mcd(int n) => File(p.join(memcards, 'Mcd00$n.ps2'));
  final newAc5 = {'BASLUS-20851AC5/BASLUS-20851AC5': pattern(9, 50000), 'BASLUS-20851AC5/icon.sys': pattern(8, 964)};

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pcsx2_file_cards_');
    env = await Pcsx2TestEnv.create(tempDir);
    memcards = p.join(env.exeDir, 'memcards');
  });

  tearDown(() => tempDir.delete(recursive: true));

  group('push', () {
    test('only this game\'s saves leave the file card, as save folders', () async {
      mcd(1).writeAsBytesSync(card([gt4, ac5, ratchet]));
      final files = await env.strategy.getSaveFilesWithScreenshots(game, romPath());
      expect(files.keys.map((f) => p.basename(f.path)), ['BASLUS-20851AC5']);
      expect(folderContents(Directory(files.keys.single.path)), filesOf(ac5));
      expect(p.isWithin(memcards, files.keys.single.path), isFalse);
    });

    test('local backups keep the whole card', () async {
      mcd(1).writeAsBytesSync(card([gt4, ac5]));
      expect((await env.strategy.getSaveFiles(game, romPath())).map((f) => p.basename(f.path)), ['Mcd001.ps2']);
    });

    test('nothing for a game without saves on the card, or a card that can\'t be read', () async {
      mcd(1).writeAsBytesSync(card([gt4]));
      mcd(2).writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      expect(await env.strategy.getSaveFilesWithScreenshots(game, romPath()), isEmpty);
    });

    test('serial unknown: nothing is uploaded, and the user is told why', () async {
      mcd(1).writeAsBytesSync(card([gt4, ac5]));
      expect(await env.strategy.getSaveFilesWithScreenshots(game, romPath('Ace Combat 5.iso')), isEmpty);
      expect(await env.strategy.saveSyncBlockedReason(game, romPath('Ace Combat 5.iso')), contains('serial'));
      expect(await env.strategy.saveSyncBlockedReason(game, romPath()), isNull);
    });
  });

  group('pull onto a file card', () {
    test('this game\'s saves are replaced, every other save stays', () async {
      mcd(1).writeAsBytesSync(card([gt4, ac5, ratchet]));
      expect(await env.strategy.restoreSave(game, romPath(), zipOf(newAc5), 'Ace Combat 5.zip'), isTrue);
      final after = cardContents(mcd(1));
      expect(after.keys.toSet(), {'BESCES-52438GAMEDATA', 'BASCUS-97199RATCHET', 'BASLUS-20851AC5'});
      expect(after['BESCES-52438GAMEDATA'], filesOf(gt4));
      expect(after['BASCUS-97199RATCHET'], filesOf(ratchet));
      expect(after['BASLUS-20851AC5']!['BASLUS-20851AC5'], pattern(9, 50000).toList());
      expect(File('${mcd(1).path}.bak').existsSync(), isTrue);
      expect(Directory(p.join(memcards, 'Mcd001.ps2')).existsSync(), isFalse, reason: 'still a file card');
    });

    test('a whole card from RomM: only this game\'s saves are taken', () async {
      mcd(1).writeAsBytesSync(card([ratchet]));
      await env.strategy.restoreSave(game, romPath(), card([gt4, ac5]), 'Mcd001.ps2');
      expect(cardContents(mcd(1)).keys.toSet(), {'BASCUS-97199RATCHET', 'BASLUS-20851AC5'});
    });

    test('a local backup of the shared card puts back only this game\'s saves', () async {
      final olderAc5 = save('BASLUS-20851AC5', {'BASLUS-20851AC5': pattern(11, 40000), 'icon.sys': pattern(2, 964)});
      final backedUp = card([olderAc5, gt4]);
      final backup = Uint8List.fromList(ZipEncoder().encode(Archive()..addFile(ArchiveFile('Mcd001.ps2', backedUp.length, backedUp))));
      final newerGt4 = save('BESCES-52438GAMEDATA', {'BESCES-52438GAMEDATA': pattern(12, 124880)});
      mcd(1).writeAsBytesSync(card([ac5, newerGt4]));

      expect(await env.strategy.restoreBackup(game, romPath(), backup, 'freegosy_77_backup.zip'), isTrue);
      final after = cardContents(mcd(1));
      expect(after['BASLUS-20851AC5'], filesOf(olderAc5), reason: 'this game: back to the backup');
      expect(after['BESCES-52438GAMEDATA'], filesOf(newerGt4), reason: 'another game: untouched');
    });

    test('the card that already holds the game\'s saves gets them', () async {
      mcd(1).writeAsBytesSync(card([gt4]));
      mcd(2).writeAsBytesSync(card([ac5]));
      await env.strategy.restoreSave(game, romPath(), zipOf(newAc5), 'x.zip');
      expect(cardContents(mcd(1)).keys, ['BESCES-52438GAMEDATA']);
      expect(cardContents(mcd(2))['BASLUS-20851AC5']!['BASLUS-20851AC5'], pattern(9, 50000).toList());
    });

    test('a folder card upload from another PC, PCSX2\'s bookkeeping left out', () async {
      mcd(1).writeAsBytesSync(card([gt4]));
      await env.strategy.restoreSave(
          game,
          romPath(),
          zipOf({
            'Mcd001.ps2/_pcsx2_superblock': Uint8List(8192),
            'Mcd001.ps2/BASLUS-20851AC5/_pcsx2_index': [1],
            'Mcd001.ps2/BASLUS-20851AC5/BASLUS-20851AC5': pattern(9, 50000),
            'Mcd001.ps2/BASLUS-20502/data': [1],
          }),
          'x.zip');
      final after = cardContents(mcd(1));
      expect(after.keys.toSet(), {'BESCES-52438GAMEDATA', 'BASLUS-20851AC5'});
      expect(after['BASLUS-20851AC5']!.keys, ['BASLUS-20851AC5']);
    });

    test('a save that does not fit is refused and the card is not changed', () async {
      // 8,104 of the card's 8,135 KB used; the new save needs 52 more.
      mcd(1).writeAsBytesSync(card([save('BASLUS-99999BIG', {'big': Uint8List(8100 * 1024)})]));
      final before = mcd(1).readAsBytesSync();
      await expectLater(env.strategy.restoreSave(game, romPath(), zipOf(newAc5), 'x.zip'),
          throwsA(isA<SaveSyncNotPossibleException>()));
      expect(mcd(1).readAsBytesSync(), before);
    });

    test('a pull the launch went ahead without leaves the card alone', () async {
      mcd(1).writeAsBytesSync(card([gt4, ac5]));
      final before = mcd(1).readAsBytesSync();
      final guard = SaveRestoreGuard()..markTooLate();
      await guard.run(() => env.strategy.restoreSave(game, romPath(), zipOf(newAc5), 'x.zip'));
      expect(mcd(1).readAsBytesSync(), before);
    });

    test('serial unknown: refused, the card is not changed', () async {
      mcd(1).writeAsBytesSync(card([gt4]));
      final before = mcd(1).readAsBytesSync();
      await expectLater(env.strategy.restoreSave(game, romPath('Ace Combat 5.iso'), zipOf(newAc5), 'x.zip'),
          throwsA(isA<SaveSyncNotPossibleException>()));
      expect(mcd(1).readAsBytesSync(), before);
    });

    test('the pull finishes before PCSX2 starts', () async {
      mcd(1).writeAsBytesSync(card([gt4]));
      expect(await env.strategy.pullMustFinishBeforeLaunch(game, romPath()), isTrue);
    });
  });

  group('pull onto a folder card', () {
    late Directory folderCard;
    setUp(() {
      folderCard = Directory(p.join(memcards, 'Mcd001.ps2'))..createSync();
      File(p.join(folderCard.path, '_pcsx2_superblock')).writeAsBytesSync(Uint8List(8192));
      Directory(p.join(folderCard.path, 'BESCES-52438GAMEDATA')).createSync();
      File(p.join(folderCard.path, 'BESCES-52438GAMEDATA', 'x')).writeAsBytesSync([7]);
    });

    test('a whole file card from RomM: the game\'s saves become folders, other folders stay', () async {
      await env.strategy.restoreSave(game, romPath(), card([gt4, ac5]), 'Mcd001.ps2');
      expect(folderCard.existsSync(), isTrue, reason: 'still a folder card');
      expect(folderContents(Directory(p.join(folderCard.path, 'BASLUS-20851AC5'))), filesOf(ac5));
      expect(folderContents(Directory(p.join(folderCard.path, 'BESCES-52438GAMEDATA'))), {'x': [7]});
    });

    test('save folders go in as before', () async {
      await env.strategy.restoreSave(game, romPath(), zipOf(newAc5), 'x.zip');
      expect(folderContents(Directory(p.join(folderCard.path, 'BASLUS-20851AC5')))['BASLUS-20851AC5'],
          pattern(9, 50000).toList());
    });

    test('no wait before launch for a folder card', () async {
      expect(await env.strategy.pullMustFinishBeforeLaunch(game, romPath()), isFalse);
    });
  });

  group('no memory card yet', () {
    test('a whole card from RomM: a new file card with only this game\'s saves', () async {
      await env.strategy.restoreSave(game, romPath(), card([gt4, ac5]), 'Mcd001.ps2');
      expect(cardContents(mcd(1)).keys, ['BASLUS-20851AC5']);
    });

    test('save folders: a folder card, as before', () async {
      await env.strategy.restoreSave(game, romPath(), zipOf(newAc5), 'x.zip');
      expect(Directory(p.join(memcards, 'Mcd001.ps2', 'BASLUS-20851AC5')).existsSync(), isTrue);
    });
  });

  test('file card → folder card → file card keeps the save', () async {
    // PC 1 (file card) pushes.
    mcd(1).writeAsBytesSync(card([gt4, ac5]));
    final pushed = (await env.strategy.getSaveFilesWithScreenshots(game, romPath())).keys;
    final entries = {
      for (final d in pushed)
        for (final f in Directory(d.path).listSync().whereType<File>())
          '${p.basename(d.path)}/${p.basename(f.path)}': f.readAsBytesSync(),
    };
    // PC 2 (a folder card with another game) pulls.
    mcd(1).deleteSync();
    final folderCard = Directory(p.join(memcards, 'Mcd001.ps2'))..createSync();
    Directory(p.join(folderCard.path, 'BASCUS-97199RATCHET')).createSync();
    await env.strategy.restoreSave(game, romPath(), zipOf(entries), 'x.zip');
    expect(folderContents(Directory(p.join(folderCard.path, 'BASLUS-20851AC5'))), filesOf(ac5));
    // PC 2 pushes its folder card: the same save folders.
    final pushed2 = (await env.strategy.getSaveFilesWithScreenshots(game, romPath())).keys;
    final entries2 = {
      for (final d in pushed2)
        for (final f in Directory(d.path).listSync().whereType<File>())
          '${p.basename(d.path)}/${p.basename(f.path)}': f.readAsBytesSync(),
    };
    // PC 3 (a file card with another game) pulls.
    folderCard.deleteSync(recursive: true);
    mcd(1).writeAsBytesSync(card([ratchet]));
    await env.strategy.restoreSave(game, romPath(), zipOf(entries2), 'x.zip');
    final after = cardContents(mcd(1));
    expect(after.keys.toSet(), {'BASCUS-97199RATCHET', 'BASLUS-20851AC5'});
    expect(after['BASLUS-20851AC5'], filesOf(ac5));
  });
}
