import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/formats/ps2_memory_card.dart';

/// Cards in test/fixtures/ps2_cards are made by mymcplus, an independent
/// implementation of the PS2 memory card file system (see make_fixtures.py
/// there), so these tests check this reader and writer against someone
/// else's.
void main() {
  /// A fixture card, full size. With [ecc] off, the same card with the ECC
  /// bytes stripped from every page.
  Uint8List fixture(String name, {bool ecc = true}) {
    final bytes = gzip.decode(File('test/fixtures/ps2_cards/$name.ps2.gz').readAsBytesSync());
    final card = Uint8List(Ps2MemoryCard.sizeWithEcc)
      ..fillRange(0, Ps2MemoryCard.sizeWithEcc, 0xFF)
      ..setRange(0, bytes.length, bytes);
    if (ecc) return card;
    final out = Uint8List(Ps2MemoryCard.sizeWithoutEcc);
    for (var n = 0; n < 16384; n++) {
      out.setRange(n * 512, n * 512 + 512, card, n * 528);
    }
    return out;
  }

  /// The byte pattern make_fixtures.py fills its files with.
  Uint8List pattern(int seed, int length) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) (seed + i * 7) & 0xFF]);

  const pageRaw = 528;
  const pages = 16384;

  /// Every page's stored ECC matches its data.
  void expectValidEcc(Uint8List card) {
    for (var n = 0; n < pages; n++) {
      final at = n * pageRaw;
      final stored = card.sublist(at + 512, at + 528);
      if (stored.every((b) => b == 0xFF)) continue; // an erased page
      expect(stored, Ps2MemoryCard.eccOf(Uint8List.sublistView(card, at, at + 512)), reason: 'page $n');
    }
  }

  Ps2CardSave save(String name, Map<String, Uint8List> files) =>
      Ps2CardSave(name: name, files: [for (final e in files.entries) Ps2CardFile(name: e.key, data: e.value)]);

  group('reading', () {
    test('a formatted card has no saves and all but the root cluster free', () {
      for (final ecc in [true, false]) {
        final card = Ps2MemoryCard.parse(fixture('formatted', ecc: ecc));
        expect(card.saves, isEmpty, reason: 'ecc: $ecc');
        expect(card.freeClusters, 8135 - 1, reason: 'ecc: $ecc');
      }
    });

    test('saves and their files are read in order, deleted ones skipped', () {
      for (final ecc in [true, false]) {
        final name = 'ecc: $ecc';
        final card = Ps2MemoryCard.parse(fixture('three_saves', ecc: ecc));
        expect(card.saves.map((s) => s.name), ['BASLUS-20502', 'BESCES-52438GAMEDATA', 'BASLUS-21026-PROFILE'],
            reason: name);
        final files = {for (final s in card.saves) for (final f in s.files) '${s.name}/${f.name}': f.data};
        expect(files, {
          'BASLUS-20502/BASLUS-20502': pattern(1, 3000),
          'BASLUS-20502/icon.sys': pattern(2, 964),
          'BASLUS-20502/empty': Uint8List(0),
          'BESCES-52438GAMEDATA/BESCES-52438GAMEDATA': pattern(3, 150000),
          'BESCES-52438GAMEDATA/icon.sys': pattern(4, 964),
          'BESCES-52438GAMEDATA/view.ico': pattern(5, 33000),
          'BASLUS-21026-PROFILE/BASLUS-21026-PROFILE': pattern(6, 1024),
        }, reason: name);
        expect(card.saves.first.mode, Ps2MemoryCard.dirMode);
        expect(card.saves.first.files.first.mode, Ps2MemoryCard.fileMode);
      }
    });

    test('the ECC matches the ECC mymcplus wrote, page by page', () {
      expectValidEcc(fixture('three_saves'));
      expectValidEcc(fixture('formatted'));
    });

    test('anything but a formatted card of a known size is refused', () {
      expect(() => Ps2MemoryCard.parse(Uint8List(1000)), throwsFormatException);
      expect(() => Ps2MemoryCard.parse(Uint8List(Ps2MemoryCard.sizeWithEcc)), throwsFormatException);
      final blank = Uint8List(Ps2MemoryCard.sizeWithEcc)..fillRange(0, Ps2MemoryCard.sizeWithEcc, 0xFF);
      expect(() => Ps2MemoryCard.parse(blank), throwsFormatException);
      expect(Ps2MemoryCard.isUnformatted(blank), isTrue);
      expect(Ps2MemoryCard.isUnformatted(fixture('formatted')), isFalse);
      expect(Ps2MemoryCard.looksLikeCard(fixture('formatted')), isTrue);
      expect(Ps2MemoryCard.looksLikeCard(blank), isFalse);
    });
  });

  group('damaged cards are refused', () {
    // Clusters are 2 pages; the allocatable area starts at cluster 41 and the
    // FAT is in clusters 9..40 (256 4-byte entries per cluster).
    int fatOffset(int n) => (9 + n ~/ 256) * 2 * pageRaw + (n % 256 < 128 ? 0 : pageRaw - 512) + (n % 256) * 4;

    Uint8List withFat(Uint8List card, int n, int value) {
      final out = Uint8List.fromList(card);
      final at = fatOffset(n);
      for (var i = 0; i < 4; i++) {
        out[at + i] = value >> (8 * i) & 0xFF;
      }
      return out;
    }

    int fatOf(Uint8List card, int n) {
      final at = fatOffset(n);
      return card[at] | card[at + 1] << 8 | card[at + 2] << 16 | card[at + 3] << 24;
    }

    // A card written by this class: the root at cluster 0, then each save's
    // directory and files packed in order.
    final one = Ps2MemoryCard.parse(Ps2MemoryCard.formatted(now: DateTime.utc(2026)))
        .withSaves([save('BASLUS-20502', {'data': pattern(1, 5000)})], (_) => false);

    test('the helper finds the FAT', () {
      // root (3 entries: 2 clusters), save dir (3 entries: 2 clusters), file (5).
      expect([for (var n = 0; n < 10; n++) fatOf(one, n)], [
        0x80000001, 0xFFFFFFFF, // root
        0x80000003, 0xFFFFFFFF, // save directory
        0x80000005, 0x80000006, 0x80000007, 0x80000008, 0xFFFFFFFF, // file
        0x7FFFFFFF, // free
      ]);
      expect(Ps2MemoryCard.parse(one).saves.single.files.single.data, pattern(1, 5000));
    });

    test('a chain that loops', () {
      expect(() => Ps2MemoryCard.parse(withFat(one, 5, 0x80000004)), throwsFormatException);
    });

    test('a chain that runs into a free cluster', () {
      expect(() => Ps2MemoryCard.parse(withFat(one, 5, 0x00000006)), throwsFormatException);
    });

    test('a file shorter than its length', () {
      expect(() => Ps2MemoryCard.parse(withFat(one, 5, 0xFFFFFFFF)), throwsFormatException);
    });

    test('a link out of range', () {
      expect(() => Ps2MemoryCard.parse(withFat(one, 5, 0x80000000 | 9000)), throwsFormatException);
    });
  });

  group('writing', () {
    test('replacing one game\'s saves keeps the others, byte for byte', () {
      final before = Ps2MemoryCard.parse(fixture('three_saves'));
      final incoming = save('BASLUS-20502', {'BASLUS-20502': pattern(9, 7000), 'icon.sys': pattern(8, 964)});
      final bytes = before.withSaves([incoming], (n) => n.startsWith('BASLUS-20502'));
      final after = Ps2MemoryCard.parse(bytes);

      expect(after.saves.map((s) => s.name), ['BESCES-52438GAMEDATA', 'BASLUS-21026-PROFILE', 'BASLUS-20502']);
      for (final kept in before.saves.skip(1)) {
        final now = after.saves.firstWhere((s) => s.name == kept.name);
        expect(now.mode, kept.mode);
        expect(now.created, kept.created);
        expect(now.modified, kept.modified);
        List<Object> described(Ps2CardSave s) => [
              for (final f in s.files) [f.name, f.data.toList(), f.mode, f.attr, f.created.toList(), f.modified.toList()],
            ];
        expect(described(now), described(kept));
      }
      final replaced = after.saves.last;
      expect({for (final f in replaced.files) f.name: f.data},
          {'BASLUS-20502': pattern(9, 7000), 'icon.sys': pattern(8, 964)});
      expectValidEcc(bytes);
    });

    test('everything outside the FAT and the save area stays as it was', () {
      final source = fixture('three_saves');
      final bytes = Ps2MemoryCard.parse(source).withSaves(const [], (n) => n == 'BASLUS-21026-PROFILE');
      Uint8List clusters(Uint8List card, int from, int to) => card.sublist(from * 2 * pageRaw, to * 2 * pageRaw);
      expect(clusters(bytes, 0, 9), clusters(source, 0, 9), reason: 'superblock, pages 1-15, indirect FAT');
      expect(bytes.sublist((41 + 8135) * 2 * pageRaw), source.sublist((41 + 8135) * 2 * pageRaw),
          reason: 'the two backup blocks');
      expect(Ps2MemoryCard.parse(bytes).saves.map((s) => s.name), ['BASLUS-20502', 'BESCES-52438GAMEDATA']);
    });

    test('the same saves give the same card', () {
      final card = Ps2MemoryCard.parse(fixture('three_saves'));
      final incoming = save('BASLUS-20502', {'x': pattern(1, 10)});
      expect(card.withSaves([incoming], (n) => n == 'BASLUS-20502'),
          card.withSaves([incoming], (n) => n == 'BASLUS-20502'));
    });

    test('a card without ECC stays without ECC', () {
      final bytes = Ps2MemoryCard.parse(fixture('three_saves', ecc: false)).withSaves(const [], (_) => false);
      expect(bytes.length, Ps2MemoryCard.sizeWithoutEcc);
      expect(Ps2MemoryCard.parse(bytes).saves, hasLength(3));
    });

    test('an incoming save with the name of a save that stays replaces it', () {
      final card = Ps2MemoryCard.parse(fixture('three_saves'));
      final bytes = card.withSaves([save('BASLUS-21026-PROFILE', {'p': pattern(1, 1)})], (_) => false);
      final after = Ps2MemoryCard.parse(bytes);
      expect(after.saves.where((s) => s.name == 'BASLUS-21026-PROFILE'), hasLength(1));
      expect(after.saves.last.files.single.name, 'p');
    });

    test('a save that does not fit is refused and the card is not changed', () {
      final source = fixture('three_saves');
      final card = Ps2MemoryCard.parse(source);
      expect(() => card.withSaves([save('BIG', {'big': Uint8List(8135 * 1024)})], (_) => false),
          throwsA(isA<Ps2CardFullException>()));
      expect(Ps2MemoryCard.parse(source).saves, hasLength(3));
    });

    test('a save that exactly fills the card fits', () {
      final card = Ps2MemoryCard.parse(Ps2MemoryCard.formatted(now: DateTime.utc(2026)));
      // root (3 entries: 2 clusters) + save dir (3 entries: 2 clusters) + file.
      final bytes = card.withSaves([save('FULL', {'f': Uint8List((8135 - 4) * 1024)})], (_) => false);
      expect(Ps2MemoryCard.parse(bytes).freeClusters, 0);
    });

    test('many saves spill the root over several clusters', () {
      final card = Ps2MemoryCard.parse(Ps2MemoryCard.formatted(now: DateTime.utc(2026)));
      final many = [for (var i = 0; i < 40; i++) save('BASLUS-2${i.toString().padLeft(4, '0')}', {'d': pattern(i, 100)})];
      final after = Ps2MemoryCard.parse(card.withSaves(many, (_) => false));
      expect(after.saves.map((s) => s.name), many.map((s) => s.name));
      expect(after.saves[39].files.single.data, pattern(39, 100));
    });

    test('a formatted card reads back as an empty card', () {
      for (final ecc in [true, false]) {
        final bytes = Ps2MemoryCard.formatted(ecc: ecc, now: DateTime.utc(2026));
        expect(bytes.length, ecc ? Ps2MemoryCard.sizeWithEcc : Ps2MemoryCard.sizeWithoutEcc);
        final card = Ps2MemoryCard.parse(bytes);
        expect(card.saves, isEmpty);
        expect(card.freeClusters, 8135 - 1);
        if (ecc) expectValidEcc(bytes);
      }
    });

    test('names longer than the card allows are refused', () {
      final card = Ps2MemoryCard.parse(Ps2MemoryCard.formatted(now: DateTime.utc(2026)));
      expect(() => card.withSaves([save('X' * 33, {'f': Uint8List(1)})], (_) => false), throwsArgumentError);
    });
  });

  test('time records are in Japan time', () {
    expect(Ps2MemoryCard.timeRecord(DateTime.utc(2026, 9, 26, 15, 4, 5)), [0, 5, 4, 0, 27, 9, 0xEA, 0x07]);
  });
}
