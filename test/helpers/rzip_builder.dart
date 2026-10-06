import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

/// [raw] as RetroArch's RZIP (libretro-common/streams/rzip_stream.c): the
/// 20-byte header `#RZIPv<version>#`, chunk size (u32 LE), total size (u64
/// LE), then per chunk its compressed length (u32 LE) and data. Deflate
/// chunks are zlib-wrapped; pass [compress] for version 2 (zstd).
Uint8List buildRzip(Uint8List raw,
    {int version = 1, int chunkSize = 131072, Uint8List Function(Uint8List chunk)? compress}) {
  final pack = compress ?? (Uint8List chunk) => Uint8List.fromList(ZLibEncoder().convert(chunk));
  final out = BytesBuilder();
  out.add([0x23, 0x52, 0x5A, 0x49, 0x50, 0x76, version, 0x23]);
  final head = ByteData(12)
    ..setUint32(0, chunkSize, Endian.little)
    ..setUint32(4, raw.length, Endian.little)
    ..setUint32(8, 0, Endian.little);
  out.add(head.buffer.asUint8List());
  for (var start = 0; start < raw.length; start += chunkSize) {
    final end = start + chunkSize < raw.length ? start + chunkSize : raw.length;
    final packed = pack(Uint8List.sublistView(raw, start, end));
    out.add((ByteData(4)..setUint32(0, packed.length, Endian.little)).buffer.asUint8List());
    out.add(packed);
  }
  return out.takeBytes();
}
