import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/formats/rzip.dart';

import '../helpers/rzip_builder.dart';

void main() {
  final raw = Uint8List.fromList(List.generate(2500, (i) => (i * 7) % 251));

  test('a deflate RZIP of several chunks, the last one short, unpacks to the original', () async {
    final packed = buildRzip(raw, chunkSize: 1024);
    expect(Rzip.isRzip(packed), isTrue);
    expect(await Rzip.unpack(packed), raw);
  });

  test('a zstd RZIP (version 2) unpacks through the zstd decompressor', () async {
    // Stands in for zstd: a "compressed" chunk is the chunk behind a 0xAA marker.
    Uint8List fakeCompress(Uint8List c) => Uint8List.fromList([0xAA, ...c]);
    Future<Uint8List?> fakeZstd(Uint8List c) async => c.first == 0xAA ? Uint8List.sublistView(c, 1) : null;
    final packed = buildRzip(raw, version: 2, chunkSize: 1024, compress: fakeCompress);
    expect(await Rzip.unpack(packed, zstd: fakeZstd), raw);
  });

  test('plain saves are not RZIP', () {
    expect(Rzip.isRzip(raw), isFalse);
    expect(Rzip.isRzip(Uint8List.fromList('#RZIPv'.codeUnits)), isFalse, reason: 'shorter than the header');
    final v3 = buildRzip(raw)..[6] = 3;
    expect(Rzip.isRzip(v3), isFalse, reason: 'unknown version');
  });

  test('malformed RZIP files are refused', () async {
    final zeroChunk = buildRzip(raw)..setRange(8, 12, [0, 0, 0, 0]);
    await expectLater(Rzip.unpack(zeroChunk), throwsFormatException);

    final truncated = Uint8List.sublistView(buildRzip(raw, chunkSize: 1024), 0, 60);
    await expectLater(Rzip.unpack(truncated), throwsFormatException);

    final claimsMore = buildRzip(raw, chunkSize: 1024);
    ByteData.sublistView(claimsMore).setUint32(12, raw.length + 10, Endian.little);
    await expectLater(Rzip.unpack(claimsMore), throwsFormatException);

    final hugeChunk = buildRzip(raw, chunkSize: 1024);
    ByteData.sublistView(hugeChunk).setUint32(20, 1024 * 2 + 1, Endian.little);
    await expectLater(Rzip.unpack(hugeChunk), throwsFormatException);

    await expectLater(Rzip.unpack(raw), throwsFormatException);
  });

  test('a zstd chunk that does not decompress is refused', () async {
    final packed = buildRzip(raw, version: 2, compress: (c) => c);
    await expectLater(Rzip.unpack(packed, zstd: (_) async => null), throwsFormatException);
  });
}
