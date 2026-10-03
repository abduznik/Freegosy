import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/formats/ps1_memory_card.dart';

import '../helpers/ps1_card_builder.dart';

void main() {
  bool colin(String name) => name.length >= 12 && name.substring(2, 12) == 'SLES-02605';

  final colinSetting = (name: 'BESLES-02605-SETTING', blocks: [1], fill: 0x11);
  final colinGame = (name: "BESLES-02605&0<'X)G|", blocks: [2, 3, 4], fill: 0x22);
  final other = (name: 'BASLUS-00594GAME', blocks: [5, 6], fill: 0x33);

  group('parse', () {
    test('lists every save with its name and block chain, and the free blocks', () {
      final card = Ps1MemoryCard.parse(buildPs1Card([colinSetting, colinGame, other]));

      expect(card.saves.map((s) => s.name), ['BESLES-02605-SETTING', "BESLES-02605&0<'X)G|", 'BASLUS-00594GAME']);
      expect(card.saves[1].blocks, [2, 3, 4]);
      expect(card.freeBlocks, 9);
    });

    test('follows chains that are not in block order', () {
      final card = Ps1MemoryCard.parse(buildPs1Card([(name: 'BESLES-02605X', blocks: [9, 3, 12], fill: 1)]));

      expect(card.saves.single.blocks, [9, 3, 12]);
    });

    test('a deleted save counts as free space, not as a save', () {
      final bytes = buildPs1Card([colinSetting, other]);
      bytes[1 * 128] = 0xA1; // deleted, first block
      bytes[1 * 128 + 127] ^= 0x51 ^ 0xA1;

      final card = Ps1MemoryCard.parse(bytes);

      expect(card.saves.map((s) => s.name), ['BASLUS-00594GAME']);
      expect(card.freeBlocks, 13);
    });

    test('rejects a file that is not a memory card', () {
      expect(() => Ps1MemoryCard.parse(Uint8List(1000)), throwsFormatException);
      final noHeader = buildPs1Card([])..[0] = 0;
      expect(() => Ps1MemoryCard.parse(noHeader), throwsFormatException);
    });

    test('rejects a broken chain: a loop, a link to a free block, or a wrong size', () {
      final loop = buildPs1Card([colinGame]);
      ByteData.sublistView(loop, 4 * 128).setUint16(8, 2, Endian.little); // last → block 3 again: 3 ↔ 4
      expect(() => Ps1MemoryCard.parse(loop), throwsFormatException);

      final toFree = buildPs1Card([colinGame]);
      ByteData.sublistView(toFree, 3 * 128).setUint16(8, 9, Endian.little); // → block 10, free
      expect(() => Ps1MemoryCard.parse(toFree), throwsFormatException);

      final size = buildPs1Card([colinGame]);
      ByteData.sublistView(size, 2 * 128).setUint32(4, 8192, Endian.little); // says 1 block, has 3
      expect(() => Ps1MemoryCard.parse(size), throwsFormatException);
    });

    test('rejects a block claimed by two saves', () {
      final shared = buildPs1Card([colinGame, other]);
      ByteData.sublistView(shared, 4 * 128).setUint16(8, 5, Endian.little); // 2 → 3 → 4 → 6, other's last block
      ByteData.sublistView(shared, 2 * 128).setUint32(4, 4 * 8192, Endian.little); // and the size says 4 blocks
      expect(() => Ps1MemoryCard.parse(shared), throwsFormatException);
    });
  });

  group('extract', () {
    test('a card with only the matching saves, packed from block 1, others\' data gone', () {
      final source = buildPs1Card([other, colinSetting, colinGame]);

      final extracted = Ps1MemoryCard.parse(Ps1MemoryCard.parse(source).extract(colin));

      expect(extracted.saves.map((s) => s.name), ['BESLES-02605-SETTING', "BESLES-02605&0<'X)G|"]);
      expect(extracted.saves[0].blocks, [1]);
      expect(extracted.saves[1].blocks, [2, 3, 4]);
      expect(extracted.freeBlocks, 11);
    });

    test('block data travels with its save, in chain order', () {
      final source = buildPs1Card([(name: 'BESLES-02605X', blocks: [9, 3, 12], fill: 0x44)]);

      final bytes = Ps1MemoryCard.parse(source).extract(colin);

      expect(blockData(bytes, 1), blockData(source, 9));
      expect(blockData(bytes, 2), blockData(source, 3));
      expect(blockData(bytes, 3), blockData(source, 12));
      expect(blockData(bytes, 4), everyElement(0xFF), reason: 'free blocks as DuckStation formats them');
    });

    test('the same saves give the same bytes, wherever they sit and whatever else is on the card', () {
      final a = buildPs1Card([other, colinSetting, colinGame], writeTestByte: 7);
      final b = buildPs1Card([
        (name: colinSetting.name, blocks: [11], fill: colinSetting.fill),
        (name: colinGame.name, blocks: [14, 12, 13], fill: colinGame.fill),
      ], writeTestByte: 9);

      expect(Ps1MemoryCard.parse(a).extract(colin), Ps1MemoryCard.parse(b).extract(colin));
    });

    test('a card with a single save is a valid freshly formatted card plus that save', () {
      final extracted = Ps1MemoryCard.parse(buildPs1Card([colinSetting])).extract(colin);
      final expected = buildPs1Card([colinSetting]);

      expect(extracted, expected);
    });
  });

  group('replaceSaves', () {
    test('replaces this game\'s saves and leaves every other save byte for byte', () {
      final local = buildPs1Card([colinSetting, other, (name: 'BESLES-02605OLD', blocks: [7], fill: 0x55)]);
      final incoming = buildPs1Card([(name: 'BESLES-02605NEW', blocks: [1, 2], fill: 0x66)]);

      final merged = Ps1MemoryCard.parse(local).replaceSaves(Ps1MemoryCard.parse(incoming), colin)!;
      final card = Ps1MemoryCard.parse(merged);

      expect(card.saves.map((s) => s.name), containsAll(['BASLUS-00594GAME', 'BESLES-02605NEW']));
      expect(card.saves.map((s) => s.name), isNot(contains('BESLES-02605-SETTING')));
      expect(card.saves.map((s) => s.name), isNot(contains('BESLES-02605OLD')));
      for (final block in [5, 6]) {
        expect(blockData(merged, block), blockData(local, block));
        expect(merged.sublist(block * 128, block * 128 + 128), local.sublist(block * 128, block * 128 + 128));
      }
      final added = card.saves.firstWhere((s) => s.name == 'BESLES-02605NEW');
      expect(added.blocks.map((b) => blockData(merged, b)), [blockData(incoming, 1), blockData(incoming, 2)]);
    });

    test('the replaced saves are marked deleted, as the PS1 does', () {
      final local = buildPs1Card([colinGame, other]);
      final incoming = buildPs1Card([(name: 'BESLES-02605NEW', blocks: [1], fill: 0x66)]);

      final merged = Ps1MemoryCard.parse(local).replaceSaves(Ps1MemoryCard.parse(incoming), colin)!;

      // The new save takes the lowest free block, 1; the old one's blocks
      // 2–4 stay behind as deleted first/middle/last.
      expect(entryState(merged, 1), 0x51);
      expect([entryState(merged, 2), entryState(merged, 3), entryState(merged, 4)], [0xA1, 0xA2, 0xA3]);
    });

    test('other games\' saves on the incoming card are ignored', () {
      final local = buildPs1Card([other]);
      final incoming = buildPs1Card([colinSetting, (name: 'BASCUS-94163FF7', blocks: [2], fill: 0x77)]);

      final card = Ps1MemoryCard.parse(
          Ps1MemoryCard.parse(local).replaceSaves(Ps1MemoryCard.parse(incoming), colin)!);

      expect(card.saves.map((s) => s.name).toSet(), {'BASLUS-00594GAME', 'BESLES-02605-SETTING'});
    });

    test('null when the incoming card holds none of this game\'s saves: nothing to change', () {
      final local = buildPs1Card([colinSetting]);

      expect(Ps1MemoryCard.parse(local).replaceSaves(Ps1MemoryCard.parse(buildPs1Card([other])), colin), isNull);
    });

    test('a save uses scattered free blocks, and the chain links them', () {
      final local = buildPs1Card([
        (name: 'BASLUS-00001A', blocks: [1, 2], fill: 1),
        (name: 'BASLUS-00002B', blocks: [4], fill: 2),
        (name: 'BASLUS-00003C', blocks: [6, 7, 8, 9, 10, 11, 12, 13, 14, 15], fill: 3),
      ]);
      final incoming = buildPs1Card([(name: 'BESLES-02605BIG', blocks: [1, 2], fill: 0x66)]);

      final card = Ps1MemoryCard.parse(
          Ps1MemoryCard.parse(local).replaceSaves(Ps1MemoryCard.parse(incoming), colin)!);

      expect(card.saves.firstWhere((s) => s.name == 'BESLES-02605BIG').blocks, [3, 5]);
    });

    test('not enough free blocks: throws, telling how many are needed and free', () {
      final local = buildPs1Card([(name: 'BASLUS-00003C', blocks: List.generate(14, (i) => i + 1), fill: 3)]);
      final incoming = buildPs1Card([(name: 'BESLES-02605BIG', blocks: [1, 2], fill: 0x66)]);

      expect(
        () => Ps1MemoryCard.parse(local).replaceSaves(Ps1MemoryCard.parse(incoming), colin),
        throwsA(isA<Ps1CardFullException>()
            .having((e) => e.needed, 'needed', 2)
            .having((e) => e.free, 'free', 1)),
      );
    });

    test('space freed by this game\'s old saves is reused', () {
      final local = buildPs1Card([
        (name: 'BASLUS-00003C', blocks: List.generate(13, (i) => i + 1), fill: 3),
        (name: 'BESLES-02605OLD', blocks: [14, 15], fill: 0x55),
      ]);
      final incoming = buildPs1Card([(name: 'BESLES-02605NEW', blocks: [1, 2], fill: 0x66)]);

      final card = Ps1MemoryCard.parse(
          Ps1MemoryCard.parse(local).replaceSaves(Ps1MemoryCard.parse(incoming), colin)!);

      expect(card.saves.firstWhere((s) => s.name == 'BESLES-02605NEW').blocks, [14, 15]);
    });
  });
}
