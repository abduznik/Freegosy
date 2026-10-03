import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'zstd.dart';

/// RetroArch's RZIP, which it writes every save in when "SaveRAM
/// compression" is on (off by default). Layout from
/// libretro-common/streams/rzip_stream.c: a 20-byte header (`#RZIPv`, a
/// version byte, `#`, chunk size as u32 LE, uncompressed size as u64 LE),
/// then chunks, each a compressed length (u32 LE) and that many bytes.
/// Version 1 chunks are zlib-wrapped deflate, version 2 zstd frames.
class Rzip {
  Rzip._();

  static const headerSize = 20;
  static const _deflate = 1;
  static const _zstd = 2;
  static const _maxChunkSize = 64 * 1024 * 1024;
  static const _magic = [0x23, 0x52, 0x5A, 0x49, 0x50, 0x76]; // "#RZIPv"

  static bool isRzip(Uint8List bytes) {
    if (bytes.length < headerSize) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return (bytes[6] == _deflate || bytes[6] == _zstd) && bytes[7] == 0x23;
  }

  /// The uncompressed save. Throws [FormatException] when [bytes] isn't a
  /// well-formed RZIP file. [zstd] decompresses version 2 chunks (the
  /// zstandard plugin unless a test passes a fake).
  static Future<Uint8List> unpack(Uint8List bytes, {ZstdDecompressor? zstd}) async {
    if (!isRzip(bytes)) throw const FormatException('not an RZIP file');
    final data = ByteData.sublistView(bytes);
    final version = bytes[6];
    final chunkSize = data.getUint32(8, Endian.little);
    // Two u32 halves: ByteData.getUint64 is not available on the web.
    final total = data.getUint32(12, Endian.little) + data.getUint32(16, Endian.little) * 0x100000000;
    if (chunkSize == 0 || chunkSize > _maxChunkSize) {
      throw FormatException('RZIP chunk size $chunkSize');
    }

    final out = BytesBuilder(copy: false);
    var pos = headerSize;
    while (out.length < total) {
      if (pos + 4 > bytes.length) throw const FormatException('RZIP file ends before its last chunk');
      final length = data.getUint32(pos, Endian.little);
      pos += 4;
      if (length == 0 || length > chunkSize * 2) throw FormatException('RZIP chunk of $length bytes');
      if (pos + length > bytes.length) throw const FormatException('RZIP file ends inside a chunk');
      final packed = Uint8List.sublistView(bytes, pos, pos + length);
      pos += length;
      final Uint8List? chunk = version == _deflate
          ? Uint8List.fromList(ZLibDecoder().convert(packed))
          : await (zstd ?? zstandardDecompress)(packed);
      if (chunk == null || chunk.isEmpty || chunk.length > chunkSize) {
        throw const FormatException('RZIP chunk did not decompress');
      }
      out.add(chunk);
    }
    if (out.length != total) throw FormatException('RZIP holds ${out.length} bytes, its header says $total');
    return out.takeBytes();
  }
}
