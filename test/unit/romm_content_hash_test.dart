import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/romm_content_hash.dart';

/// RomM's own formula (backend/handler/filesystem/assets_handler.py,
/// rommapp/romm 5b3d0bf): a plain file is the md5 of its bytes; a zip is the
/// md5 of `<name>:<md5 of entry>` lines, sorted by name, joined with "\n",
/// folders skipped.
void main() {
  String md5Of(List<int> b) => md5.convert(b).toString();
  final x = Uint8List.fromList(List.generate(300, (i) => i % 251));
  final y = Uint8List.fromList(utf8.encode('card data'));

  test('a plain file: the md5 of its bytes', () {
    expect(rommHashOfFile(x), md5Of(x));
  });

  test('zip entries: md5 of sorted "name:md5" lines joined with a newline', () {
    final expected = md5Of(utf8.encode('a/c.dat:${md5Of(y)}\nb.sav:${md5Of(x)}'));
    expect(rommHashOfZipEntries({'b.sav': x, 'a/c.dat': y}), expected);
  });

  test('a zip upload hashes its contents: entry times, compression and folders don\'t matter', () {
    Uint8List zip(DateTime when, {int level = 6}) {
      final archive = Archive()
        ..addFile(ArchiveFile.directory('a/'))
        ..addFile(ArchiveFile('b.sav', x.length, x)..lastModTime = when.millisecondsSinceEpoch ~/ 1000)
        ..addFile(ArchiveFile('a/c.dat', y.length, y)..lastModTime = when.millisecondsSinceEpoch ~/ 1000);
      return Uint8List.fromList(ZipEncoder().encode(archive, level: level));
    }

    final expected = rommHashOfZipEntries({'b.sav': x, 'a/c.dat': y});
    expect(rommHashOfUpload(zip(DateTime(2026, 1, 1))), expected);
    expect(rommHashOfUpload(zip(DateTime(2026, 10, 3), level: 0)), expected);
  });

  test('a non-zip upload is hashed as a plain file', () {
    expect(rommHashOfUpload(x), md5Of(x));
  });

  test('from file digests: same formula; two files of one name both count, in their zip order', () {
    expect(rommHashOfDigests([('b.sav', md5Of(x)), ('a/c.dat', md5Of(y))]), rommHashOfZipEntries({'b.sav': x, 'a/c.dat': y}));
    expect(rommHashOfDigests([('save.dat', 'm1'), ('save.dat', 'm2')]), md5Of(utf8.encode('save.dat:m1\nsave.dat:m2')));
    expect(rommHashOfDigests([('save.dat', 'm2'), ('save.dat', 'm1')]), md5Of(utf8.encode('save.dat:m2\nsave.dat:m1')));
  });

  test('a file is hashed as a stream, the same as its bytes', () async {
    final dir = await Directory.systemTemp.createTemp('romm_hash_stream');
    addTearDown(() => dir.delete(recursive: true));
    final big = Uint8List.fromList(List.generate(3 * 1024 * 1024 + 7, (i) => i % 253));
    final file = File('${dir.path}/big.sav')..writeAsBytesSync(big);
    expect(await md5OfFile(file), md5Of(big));
  });

  // A zip Freegosy's encoder made (a nested folder, a non-ASCII name, an
  // empty file), hashed with RomM's own Python formula: 6b4e15d3….
  group('golden vector from RomM\'s Python code', () {
    const expected = '6b4e15d3dea29002c98ff93d917d607a';

    test('the zip as uploaded', () {
      final zip = File('test/fixtures/romm_hash/freegosy_bundle.zip').readAsBytesSync();
      expect(rommHashOfUpload(zip), expected);
    });

    test('the files it holds, as rommHashOfLocal lists them', () {
      String md5Bytes(List<int> b) => md5.convert(b).toString();
      expect(
          rommHashOfDigests([
            ('Spara/profiler/åäö/slot.sav', md5Bytes(List.generate(1000, (i) => i % 256))),
            ('Spara/tom.dat', md5Bytes(const [])),
            ('Spel – sparning.srm', md5Bytes(List.generate(2048, (i) => (i * 7) % 256))),
            ('freegosy_sync.txt', md5Bytes(utf8.encode('{"contentHash":"0123"}'))),
          ]),
          expected);
    });
  });

  group('what counts as a zip, as Python\'s zipfile.is_zipfile decides', () {
    final zip = File('test/fixtures/romm_hash/freegosy_bundle.zip').readAsBytesSync();

    test('a raw save that starts like a zip but has no end record is no zip', () {
      final raw = Uint8List.fromList([0x50, 0x4B, 3, 4, ...List.filled(500, 9)]);
      expect(looksLikeZip(raw), isFalse);
      expect(rommHashOfUpload(raw), md5Of(raw));
    });

    test('a zip with data in front of it (an end record, no local header first) is a zip', () {
      final prefixed = Uint8List.fromList([...List.filled(64, 1), ...zip]);
      expect(looksLikeZip(prefixed), isTrue);
    });

    test('a zip file on disk is hashed by its contents, read from the file', () async {
      final dir = await Directory.systemTemp.createTemp('romm_zip_file');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/save.zip')..writeAsBytesSync(zip);
      expect(await rommHashOfSaveFile(file), '6b4e15d3dea29002c98ff93d917d607a');
      final raw = File('${dir.path}/save.sav')..writeAsBytesSync(x);
      expect(await rommHashOfSaveFile(raw), md5Of(x));
    });
  });

  group('saves that only look like zips', () {
    // A raw save whose last bytes happen to read as a zip end record that
    // points at a central directory of one entry which isn't there. (An end
    // record of no entries is a real empty zip, for Python too.)
    final fake = Uint8List.fromList([
      ...List.filled(300, 3),
      0x50, 0x4B, 5, 6, 0, 0, 0, 0, 1, 0, 1, 0, 46, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ]);

    test('can\'t be read as a zip: no hash, as RomM stores none (Python calls it a zip, then cannot open it)', () async {
      expect(rommHashOfUpload(fake), isNull);
      final dir = await Directory.systemTemp.createTemp('romm_fake_zip');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/save.sav')..writeAsBytesSync(fake);
      expect(await rommHashOfSaveFile(file), isNull);
    });

    test('the last end marker decides, as Python\'s rfind: one too near the end means no zip', () {
      final tail = Uint8List.fromList([
        ...List.filled(50, 1),
        0x50, 0x4B, 5, 6, ...List.filled(18, 0), // a complete end record
        ...List.filled(10, 2), 0x50, 0x4B, 5, 6, ...List.filled(6, 0), // and a later, cut-off one
      ]);
      expect(looksLikeZip(tail), isFalse);
    });

    test('a zip with a comment is still the same zip, from bytes and from the file', () async {
      final zip = File('test/fixtures/romm_hash/freegosy_bundle.zip').readAsBytesSync();
      // Set the end record's comment length and append the comment.
      final commented = Uint8List.fromList([...zip.sublist(0, zip.length - 2), 5, 0, ...'hello'.codeUnits]);
      final dir = await Directory.systemTemp.createTemp('romm_comment');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/c.zip')..writeAsBytesSync(commented);
      expect(rommHashOfUpload(commented), '6b4e15d3dea29002c98ff93d917d607a');
      expect(await rommHashOfSaveFile(file), '6b4e15d3dea29002c98ff93d917d607a');
    });

    test('bytes and file agree, also for a zip with data in front of it', () async {
      final zip = File('test/fixtures/romm_hash/freegosy_bundle.zip').readAsBytesSync();
      final prefixed = Uint8List.fromList([...List.filled(64, 1), ...zip]);
      final dir = await Directory.systemTemp.createTemp('romm_agree');
      addTearDown(() => dir.delete(recursive: true));
      for (final bytes in [zip, prefixed, fake]) {
        final file = File('${dir.path}/s.bin')..writeAsBytesSync(bytes);
        expect(await rommHashOfSaveFile(file), rommHashOfUpload(bytes));
      }
    });
  });
}
