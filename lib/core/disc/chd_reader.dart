import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart' show InputMemoryStream, LzmaDecoder;
import 'package:zstandard/zstandard.dart';

import 'chd_bits.dart';
import 'chd_exception.dart';

export 'chd_exception.dart';

/// Decompresses one zstd frame; null when it can't. The zstandard plugin
/// by default; tests pass a stand-in (the plugin needs a running app).
typedef ChdZstd = Future<Uint8List?> Function(Uint8List frame);

Future<Uint8List?> _pluginZstd(Uint8List frame) => Zstandard().decompress(frame);

/// Reads the disc inside a CHD v5 file (MAME's compressed disc image)
/// without chdman. Ported from libchdr (https://github.com/rtissera/libchdr,
/// BSD-3-Clause), libchdr_chd.c and its codecs.
///
/// A CHD stores its disc in hunks (fixed-size blocks), each compressed with
/// one of up to four codecs named in the header, or stored as is, or a copy
/// of an earlier hunk. A Huffman-coded map says which. Read: zlib, LZMA,
/// Huffman and zstd, and the CD versions of zlib, LZMA and zstd. Not read
/// (a [ChdException]): FLAC (audio tracks), parent CHDs, CHD versions before 5.
class ChdReader {
  ChdReader._(this._file, this._zstd);

  final io.RandomAccessFile _file;
  final ChdZstd _zstd;

  late final List<int> _codecs;

  /// The size of the disc.
  late final int logicalBytes;
  late final int hunkBytes;

  /// The size of one sector: 2048 for a DVD; 2448 for a CD (2352 bytes of
  /// raw sector, then 96 of subcode, which this reader leaves zero).
  late final int unitBytes;
  late final int _hunkCount;

  // The map, one entry per hunk.
  late final Uint8List _types;
  late final Uint32List _lengths;
  late final List<int> _offsets;

  final _cache = <int, Uint8List>{};

  static Future<ChdReader> open(String path, {ChdZstd zstd = _pluginZstd}) async {
    final file = await io.File(path).open();
    final reader = ChdReader._(file, zstd);
    try {
      await reader._readHeader();
      await reader._readMap();
      return reader;
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  Future<void> close() => _file.close();

  /// [length] bytes of the disc from [offset].
  Future<Uint8List> read(int offset, int length) async {
    if (offset < 0 || length < 0 || offset + length > logicalBytes) {
      throw RangeError('$offset+$length is outside the disc ($logicalBytes bytes)');
    }
    final out = Uint8List(length);
    var done = 0;
    while (done < length) {
      final position = offset + done;
      final hunk = await _hunk(position ~/ hunkBytes);
      final start = position % hunkBytes;
      final count = (hunkBytes - start) < (length - done) ? hunkBytes - start : length - done;
      out.setRange(done, done + count, hunk, start);
      done += count;
    }
    return out;
  }

  Future<Uint8List> _readAt(int offset, int length) async {
    await _file.setPosition(offset);
    final bytes = await _file.read(length);
    if (bytes.length != length) throw const ChdException('the file ends early');
    return bytes;
  }

  static const _headerBytes = 124;

  Future<void> _readHeader() async {
    await _file.setPosition(0);
    final bytes = await _file.read(_headerBytes);
    const magic = 'MComprHD';
    if (bytes.length < _headerBytes || String.fromCharCodes(bytes, 0, magic.length) != magic) {
      throw const ChdException('not a CHD file');
    }
    final raw = ByteData.sublistView(bytes);
    final version = raw.getUint32(12);
    if (version != 5) throw ChdException('CHD version $version (only version 5 is read)');
    _codecs = [for (var i = 0; i < 4; i++) raw.getUint32(16 + 4 * i)];
    logicalBytes = raw.getUint64(32);
    _mapOffset = raw.getUint64(40);
    hunkBytes = raw.getUint32(56);
    unitBytes = raw.getUint32(60);
    if (hunkBytes == 0 || unitBytes == 0) throw const ChdException('bad CHD header');
    _hunkCount = (logicalBytes + hunkBytes - 1) ~/ hunkBytes;
  }

  late final int _mapOffset;

  // Hunk kinds in the decoded map (libchdr's COMPRESSION_* values).
  static const _codec0 = 0, _codec3 = 3, _none = 4, _self = 5, _parent = 6;
  static const _rleSmall = 7, _rleLarge = 8, _self0 = 9, _self1 = 10, _parentSelf = 11, _parent0 = 12, _parent1 = 13;

  Future<void> _readMap() async {
    _types = Uint8List(_hunkCount);
    _lengths = Uint32List(_hunkCount);
    _offsets = List<int>.filled(_hunkCount, 0);

    if (_codecs[0] == 0) {
      // Not compressed: 4 bytes per hunk, its offset in hunks (0: zeros).
      final raw = ByteData.sublistView(await _readAt(_mapOffset, _hunkCount * 4));
      for (var i = 0; i < _hunkCount; i++) {
        _types[i] = _none;
        _lengths[i] = hunkBytes;
        _offsets[i] = raw.getUint32(4 * i) * hunkBytes;
      }
      return;
    }

    final header = ByteData.sublistView(await _readAt(_mapOffset, 16));
    final mapBytes = header.getUint32(0);
    final firstOffset = header.getUint16(4) << 32 | header.getUint32(6);
    final mapCrc = header.getUint16(10);
    final lengthBits = header.getUint8(12), selfBits = header.getUint8(13), parentBits = header.getUint8(14);
    if (lengthBits > 32 || selfBits > 32 || parentBits > 32) throw const ChdException('bad CHD map');
    final bits = ChdBitReader(await _readAt(_mapOffset + 16, mapBytes));

    // First the hunk kinds, Huffman-coded, with runs of the last kind.
    final huffman = ChdHuffman(16, 8)..importTreeRle(bits);
    var repeat = 0;
    var last = 0;
    for (var i = 0; i < _hunkCount; i++) {
      if (repeat > 0) {
        _types[i] = last;
        repeat--;
        continue;
      }
      final kind = huffman.decodeOne(bits);
      if (kind == _rleSmall) {
        _types[i] = last;
        repeat = 2 + huffman.decodeOne(bits);
      } else if (kind == _rleLarge) {
        _types[i] = last;
        repeat = 2 + 16 + (huffman.decodeOne(bits) << 4);
        repeat += huffman.decodeOne(bits);
      } else {
        _types[i] = last = kind;
      }
    }

    // Then each hunk's length and place, checked against the map's CRC as
    // libchdr lays the entries out: kind, length (24 bits), offset (48), CRC (16).
    var offset = firstOffset;
    var lastSelf = 0;
    var lastParent = 0;
    var crc = 0xFFFF;
    final entry = Uint8List(12);
    for (var i = 0; i < _hunkCount; i++) {
      var place = offset;
      var length = 0;
      var hunkCrc = 0;
      switch (_types[i]) {
        case >= _codec0 && <= _codec3:
          length = bits.read(lengthBits);
          offset += length;
          hunkCrc = bits.read(16);
        case _none:
          length = hunkBytes;
          offset += length;
          hunkCrc = bits.read(16);
        case _self:
          place = lastSelf = bits.read(selfBits);
        case _parent:
          place = lastParent = bits.read(parentBits);
        case _self1:
          lastSelf++;
          _types[i] = _self;
          place = lastSelf;
        case _self0:
          _types[i] = _self;
          place = lastSelf;
        case _parentSelf:
          _types[i] = _parent;
          place = lastParent = i * hunkBytes ~/ unitBytes;
        case _parent1:
          lastParent += hunkBytes ~/ unitBytes;
          _types[i] = _parent;
          place = lastParent;
        case _parent0:
          _types[i] = _parent;
          place = lastParent;
      }
      _lengths[i] = length;
      _offsets[i] = place;
      entry[0] = _types[i];
      entry[1] = length >> 16;
      entry[2] = length >> 8;
      entry[3] = length;
      for (var b = 0; b < 6; b++) {
        entry[4 + b] = place >> (8 * (5 - b));
      }
      entry[10] = hunkCrc >> 8;
      entry[11] = hunkCrc;
      crc = _crc16(crc, entry);
    }
    if (crc != mapCrc) throw const ChdException('the CHD map is damaged (CRC mismatch)');
  }

  Future<Uint8List> _hunk(int index) async {
    final cached = _cache[index];
    if (cached != null) return cached;
    final Uint8List data;
    switch (_types[index]) {
      case >= _codec0 && <= _codec3:
        data = await _decompress(_codecs[_types[index]], await _readAt(_offsets[index], _lengths[index]));
      case _none:
        data = _offsets[index] == 0 && _codecs[0] == 0 ? Uint8List(hunkBytes) : await _readAt(_offsets[index], hunkBytes);
      case _self:
        data = await _hunk(_offsets[index]);
      case _parent:
        throw const ChdException('this CHD needs its parent CHD');
      default:
        throw const ChdException('bad CHD map');
    }
    if (_cache.length >= 64) _cache.remove(_cache.keys.first);
    _cache[index] = data;
    return data;
  }

  static int _tag(String s) => s.codeUnits.fold(0, (v, c) => v << 8 | c);
  static final _zlib = _tag('zlib'), _lzma = _tag('lzma'), _huff = _tag('huff'), _zstdTag = _tag('zstd');
  static final _cdzl = _tag('cdzl'), _cdlz = _tag('cdlz'), _cdzs = _tag('cdzs');

  Future<Uint8List> _decompress(int codec, Uint8List src) async {
    if (codec == _zlib || codec == _lzma || codec == _zstdTag) return _base(codec, src, hunkBytes);
    if (codec == _huff) {
      final bits = ChdBitReader(src);
      final huffman = ChdHuffman(256, 16)..importTreeHuffman(bits);
      final out = Uint8List(hunkBytes);
      for (var i = 0; i < hunkBytes; i++) {
        out[i] = huffman.decodeOne(bits);
      }
      if (bits.overflowed) throw const ChdException('a Huffman hunk runs past its data');
      return out;
    }
    if (codec == _cdzl) return _cd(_zlib, src);
    if (codec == _cdlz) return _cd(_lzma, src);
    if (codec == _cdzs) return _cd(_zstdTag, src);
    throw ChdException('the ${String.fromCharCodes([codec >> 24, codec >> 16 & 255, codec >> 8 & 255, codec & 255])} '
        'codec is not read natively');
  }

  /// [src] decompressed with zlib (raw deflate), LZMA or zstd, as libchdr's
  /// codecs set them up, to [length] bytes.
  Future<Uint8List> _base(int codec, Uint8List src, int length) async {
    final Uint8List out;
    if (codec == _zlib) {
      out = Uint8List.fromList(io.ZLibDecoder(raw: true).convert(src));
    } else if (codec == _lzma) {
      // chdman's encoder settings: lc 3, lp 0, pb 2, a fresh state per hunk.
      final decoder = LzmaDecoder()..reset(literalContextBits: 3, literalPositionBits: 0, positionBits: 2, resetDictionary: true);
      out = decoder.decode(InputMemoryStream(src), length);
    } else {
      out = await _zstd(src) ?? (throw const ChdException('zstd could not decompress a hunk'));
    }
    if (out.length < length) throw const ChdException('a hunk decompressed short');
    return out.length == length ? out : Uint8List.sublistView(out, 0, length);
  }

  static const _frameBytes = 2448, _sectorBytes = 2352;
  static const _syncHeader = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00];

  /// A CD hunk: per-frame flags (sectors whose sync header and ECC chdman
  /// stripped), the sectors compressed with [baseCodec], then the subcode,
  /// which isn't read. A stripped sector gets its sync header back; its ECC
  /// stays zero.
  Future<Uint8List> _cd(int baseCodec, Uint8List src) async {
    final frames = hunkBytes ~/ _frameBytes;
    final eccBytes = (frames + 7) ~/ 8;
    final lengthBytes = hunkBytes < 65536 ? 2 : 3;
    if (src.length < eccBytes + lengthBytes) throw const ChdException('a CD hunk is truncated');
    var baseLength = src[eccBytes] << 8 | src[eccBytes + 1];
    if (lengthBytes > 2) baseLength = baseLength << 8 | src[eccBytes + 2];
    final start = eccBytes + lengthBytes;
    if (src.length < start + baseLength) throw const ChdException('a CD hunk is truncated');
    final sectors = await _base(baseCodec, Uint8List.sublistView(src, start, start + baseLength), frames * _sectorBytes);
    final out = Uint8List(hunkBytes);
    for (var f = 0; f < frames; f++) {
      out.setRange(f * _frameBytes, f * _frameBytes + _sectorBytes, sectors, f * _sectorBytes);
      if (src[f >> 3] & (1 << (f & 7)) != 0) out.setRange(f * _frameBytes, f * _frameBytes + 12, _syncHeader);
    }
    return out;
  }

  static final _crcTable = List<int>.generate(256, (i) {
    var c = i << 8;
    for (var b = 0; b < 8; b++) {
      c = (c & 0x8000) != 0 ? (c << 1) ^ 0x1021 : c << 1;
    }
    return c & 0xFFFF;
  });

  /// CRC-16/CCITT, as libchdr's crc16_update.
  static int _crc16(int crc, Uint8List data) {
    for (final b in data) {
      crc = ((crc << 8) ^ _crcTable[(crc >> 8) ^ b]) & 0xFFFF;
    }
    return crc;
  }
}
