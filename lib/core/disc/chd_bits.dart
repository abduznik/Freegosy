import 'dart:typed_data';

import 'chd_exception.dart';

// The bit reader and Huffman decoder CHD v5 uses for its hunk map and its
// "huff" codec. Ported from libchdr (https://github.com/rtissera/libchdr,
// BSD-3-Clause): libchdr_bitstream.c and libchdr_huffman.c.

/// Reads big-endian bit fields from [_data], most significant bit first.
class ChdBitReader {
  ChdBitReader(this._data);

  final Uint8List _data;
  int _buffer = 0; // 32 bits, the next bits in its top
  int _bits = 0;
  int _offset = 0;

  int peek(int count) {
    if (count == 0) return 0;
    if (count > _bits) {
      while (_bits <= 24) {
        final shift = 24 - _bits;
        if (_offset < _data.length && shift < 32) _buffer |= _data[_offset] << shift;
        _offset++;
        _bits += 8;
      }
    }
    return (_buffer & 0xFFFFFFFF) >> (32 - count);
  }

  void remove(int count) {
    _buffer = count >= 32 ? 0 : (_buffer << count) & 0xFFFFFFFF;
    _bits -= count;
  }

  int read(int count) {
    final value = peek(count);
    remove(count);
    return value;
  }

  /// Whether more was read than [_data] holds.
  bool get overflowed => _offset - _bits ~/ 8 > _data.length;
}

/// A canonical Huffman decoder for [numCodes] symbols of at most [maxBits]
/// bits, with a lookup table of 2^[maxBits] entries.
class ChdHuffman {
  ChdHuffman(this.numCodes, this.maxBits)
      : _lengths = Uint8List(numCodes),
        _codes = Uint32List(numCodes),
        _lookup = Uint32List(1 << maxBits);

  final int numCodes;
  final int maxBits;
  final Uint8List _lengths;
  final Uint32List _codes;

  /// symbol << 5 | code length, for every [maxBits]-bit window.
  final Uint32List _lookup;

  int decodeOne(ChdBitReader bits) {
    final entry = _lookup[bits.peek(maxBits)];
    bits.remove(entry & 0x1f);
    return entry >> 5;
  }

  /// Reads code lengths stored with a run-length scheme (the hunk map).
  void importTreeRle(ChdBitReader bits) {
    final fieldBits = maxBits >= 16 ? 5 : (maxBits >= 8 ? 4 : 3);
    var node = 0;
    while (node < numCodes) {
      var length = bits.read(fieldBits);
      if (length != 1) {
        _lengths[node++] = length;
        continue;
      }
      length = bits.read(fieldBits);
      if (length == 1) {
        _lengths[node++] = length;
        continue;
      }
      final repeat = bits.read(fieldBits) + 3;
      if (node + repeat > numCodes) throw const ChdException('bad Huffman tree');
      for (var i = 0; i < repeat; i++) {
        _lengths[node++] = length;
      }
    }
    _build(bits);
  }

  /// Reads code lengths that are themselves Huffman-coded (the huff codec).
  void importTreeHuffman(ChdBitReader bits) {
    final small = ChdHuffman(24, 6);
    small._lengths[0] = bits.read(3);
    final start = bits.read(3) + 1;
    var count = 0;
    for (var i = 1; i < 24; i++) {
      if (i < start || count == 7) {
        small._lengths[i] = 0;
      } else {
        count = bits.read(3);
        small._lengths[i] = count == 7 ? 0 : count;
      }
    }
    small._build(bits);

    var rleFullBits = 0;
    for (var t = numCodes - 9; t != 0; t >>= 1) {
      rleFullBits++;
    }
    var last = 0;
    var code = 0;
    while (code < numCodes) {
      final value = small.decodeOne(bits);
      if (value != 0) {
        _lengths[code++] = last = value - 1;
        continue;
      }
      var repeat = bits.read(3) + 2;
      if (repeat == 7 + 2) repeat += bits.read(rleFullBits);
      for (; repeat != 0 && code < numCodes; repeat--) {
        _lengths[code++] = last;
      }
    }
    _build(bits);
  }

  void _build(ChdBitReader bits) {
    _assignCanonicalCodes();
    _buildLookup();
    if (bits.overflowed) throw const ChdException('Huffman tree runs past its data');
  }

  void _assignCanonicalCodes() {
    final histogram = List<int>.filled(33, 0);
    for (final length in _lengths) {
      if (length > maxBits) throw const ChdException('bad Huffman tree');
      histogram[length]++;
    }
    var start = 0;
    for (var length = 32; length > 0; length--) {
      final next = (start + histogram[length]) >> 1;
      if (length != 1 && next * 2 != start + histogram[length]) throw const ChdException('bad Huffman tree');
      histogram[length] = start;
      start = next;
    }
    for (var i = 0; i < numCodes; i++) {
      if (_lengths[i] > 0) _codes[i] = histogram[_lengths[i]]++;
    }
  }

  void _buildLookup() {
    for (var i = 0; i < numCodes; i++) {
      final length = _lengths[i];
      if (length == 0) continue;
      final shift = maxBits - length;
      final first = _codes[i] << shift;
      final last = ((_codes[i] + 1) << shift) - 1;
      if (last >= _lookup.length) throw const ChdException('bad Huffman tree');
      _lookup.fillRange(first, last + 1, i << 5 | length);
    }
  }
}
