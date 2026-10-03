import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/disc/chd_disc.dart';
import 'package:freegosy/core/disc/chd_reader.dart';
import 'package:path/path.dart' as p;

/// CHDs made by chdman from two synthetic discs (see
/// test/fixtures/chd/make_fixtures.py), read back and compared with the
/// discs they were made from.
void main() {
  String fixture(String name) => p.join('test', 'fixtures', 'chd', name);
  final dvd = Uint8List.fromList(gzip.decode(File(fixture('dvd.iso.gz')).readAsBytesSync()));
  final cd = Uint8List.fromList(gzip.decode(File(fixture('cd.bin.gz')).readAsBytesSync()));
  const cdSectors = 300;

  /// zstd isn't available in unit tests (it's a Flutter plugin): this
  /// stand-in checks it is handed zstd frames and answers with a marker.
  final zstdFrames = <Uint8List>[];
  Future<Uint8List?> markerZstd(Uint8List frame) async {
    zstdFrames.add(frame);
    return Uint8List(1 << 20)..fillRange(0, 1 << 20, 0x5A);
  }

  Future<Uint8List> readAll(String name, {ChdZstd? zstd}) async {
    final chd = await ChdReader.open(fixture(name), zstd: zstd ?? markerZstd);
    try {
      return await chd.read(0, chd.logicalBytes);
    } finally {
      await chd.close();
    }
  }

  group('a DVD CHD reads back as the disc it was made from', () {
    for (final codec in ['zlib', 'lzma', 'huff', 'none']) {
      test(codec, () async {
        expect(await readAll('ps2_dvd_$codec.chd'), dvd);
      });
    }

    test('a FLAC hunk (chdman\'s default codecs) is refused, not misread', () async {
      expect(readAll('ps2_dvd_default.chd'), throwsA(isA<ChdException>()));
    });

    test('zstd hunks go to the zstd decompressor', () async {
      zstdFrames.clear();
      final bytes = await readAll('ps2_dvd_zstd.chd');
      expect(bytes.length, dvd.length);
      expect(zstdFrames, isNotEmpty);
      for (final frame in zstdFrames) {
        expect(frame.sublist(0, 4), [0x28, 0xB5, 0x2F, 0xFD], reason: 'a zstd frame starts with its magic number');
      }
      expect(bytes.sublist(0, 16), List.filled(16, 0x5A), reason: 'the decompressed hunk is what the reader returns');
    });
  });

  group('a CD CHD reads back as the disc it was made from', () {
    // Frames are 2352 bytes of sector plus 96 of subcode (left zero). chdman
    // strips the sync header and ECC of a sector whose ECC it can rebuild
    // (even sectors here); the reader puts the sync header back, so each
    // sector matches up to its ECC.
    void expectSectors(Uint8List frames) {
      expect(frames.length, greaterThanOrEqualTo(cdSectors * 2448));
      for (var lba = 0; lba < cdSectors; lba++) {
        expect(frames.sublist(lba * 2448, lba * 2448 + 2072), cd.sublist(lba * 2352, lba * 2352 + 2072),
            reason: 'sector $lba');
      }
    }

    for (final codec in ['cdzl', 'cdlz', 'default']) {
      test(codec, () async => expectSectors(await readAll('ps1_cd_$codec.chd')));
    }

    test('cdzs hunks go to the zstd decompressor', () async {
      zstdFrames.clear();
      await readAll('ps1_cd_cdzs.chd');
      expect(zstdFrames, isNotEmpty);
      expect(zstdFrames.first.sublist(0, 4), [0x28, 0xB5, 0x2F, 0xFD]);
    });
  });

  group('SYSTEM.CNF', () {
    Future<String?> cnfOf(String name) async {
      final chd = await ChdReader.open(fixture(name));
      try {
        return await readSystemCnf(chd);
      } finally {
        await chd.close();
      }
    }

    test('of a PS2 DVD, with a FLAC hunk elsewhere on the disc', () async {
      expect(await cnfOf('ps2_dvd_default.chd'), contains(r'BOOT2 = cdrom0:\SLUS_203.28;1'));
    });

    test('of a PS1 CD (raw mode 2 sectors)', () async {
      expect(await cnfOf('ps1_cd_default.chd'), contains(r'BOOT = cdrom:\SCES_012.37;1'));
    });
  });

  test('a file that is not a CHD is refused', () async {
    final dir = await Directory.systemTemp.createTemp('chd_reader_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'x.chd'))..writeAsBytesSync(List.filled(200, 7));
    expect(ChdReader.open(file.path), throwsA(isA<ChdException>()));
  });
}
