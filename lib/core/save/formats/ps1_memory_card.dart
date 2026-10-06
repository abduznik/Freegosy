import 'dart:typed_data';

/// A save on a PS1 memory card: its directory [name] (e.g.
/// `BESLES-02605-SETTING`: region, product code, then a name the game
/// chooses) and the data blocks (1–15) it occupies, in chain order.
class Ps1CardSave {
  Ps1CardSave(this.name, this.nameBytes, this.blocks);
  final String name;
  final Uint8List nameBytes;
  final List<int> blocks;
}

/// Thrown by [Ps1MemoryCard.replaceSaves] when the card lacks the room.
class Ps1CardFullException implements Exception {
  Ps1CardFullException(this.needed, this.free);
  final int needed;
  final int free;
  @override
  String toString() => 'Ps1CardFullException: $needed blocks needed, $free free';
}

/// A raw 128 KB PS1 memory card image (`.mcd`, as DuckStation and most
/// emulators store it): 16 blocks of 8 KB. Block 0 holds the header and a
/// 15-entry directory, one 128-byte frame per data block: allocation state,
/// file size, the next block of the save (block − 1, 0xFFFF at the end), the
/// file name and an XOR checksum. Blocks 1–15 hold the saves.
///
/// Used to sync one game's saves out of, and back into, a card shared by
/// every game, without touching the other games' saves.
class Ps1MemoryCard {
  Ps1MemoryCard._(this._bytes, this.saves);

  static const size = 128 * 1024;
  static const _blockSize = 8192;
  static const _frameSize = 128;
  static const _dataBlocks = 15;

  static const _inUseFirst = 0x51;
  static const _inUseMiddle = 0x52;
  static const _inUseLast = 0x53;
  static const _free = 0xA0;

  final Uint8List _bytes;

  /// The saves on the card, in the order of their first block.
  final List<Ps1CardSave> saves;

  /// Data blocks not used by a save (free or deleted).
  int get freeBlocks => _freeBlockList(_bytes).length;

  /// A quick check that [bytes] is a raw PS1 card: 128 KB starting with `MC`.
  /// This is the format of DuckStation's `.mcd` and of a RetroArch PS1 core's
  /// `.srm` alike. [parse] checks the rest.
  static bool looksLikeCard(Uint8List bytes) =>
      bytes.length == size && bytes[0] == 0x4D && bytes[1] == 0x43;

  /// Reads and checks [bytes]: the size, the `MC` header, and every save's
  /// block chain (no loops, only linked in-use blocks, the size it
  /// declares). Throws [FormatException] for anything else, so a card that
  /// isn't understood is never changed.
  factory Ps1MemoryCard.parse(Uint8List bytes) {
    if (bytes.length != size) throw FormatException('expected $size bytes, got ${bytes.length}');
    if (bytes[0] != 0x4D || bytes[1] != 0x43) throw const FormatException('no MC header');
    final saves = <Ps1CardSave>[];
    final claimed = <int>{};
    for (var first = 1; first <= _dataBlocks; first++) {
      if (_state(bytes, first) != _inUseFirst) continue;
      final blocks = <int>[first];
      var next = _next(bytes, first);
      while (next != 0xFFFF) {
        final block = next + 1;
        if (block < 1 || block > _dataBlocks) throw FormatException('block $first links to $block');
        if (blocks.contains(block)) throw FormatException('block $first has a loop');
        final state = _state(bytes, block);
        if (state != _inUseMiddle && state != _inUseLast) {
          throw FormatException('block $first links to block $block, which is not part of a save');
        }
        blocks.add(block);
        next = _next(bytes, block);
      }
      // A block in two saves' chains: replacing one save would free the
      // other's block.
      for (final block in blocks) {
        if (!claimed.add(block)) throw FormatException('block $block belongs to two saves');
      }
      final declared = ByteData.sublistView(bytes, first * _frameSize).getUint32(4, Endian.little);
      if (declared != 0 && declared != blocks.length * _blockSize) {
        throw FormatException('save at block $first says $declared bytes, has ${blocks.length} blocks');
      }
      final nameBytes = Uint8List.fromList(bytes.sublist(first * _frameSize + 0x0A, first * _frameSize + 0x1F));
      final end = nameBytes.indexOf(0);
      final name = String.fromCharCodes(end < 0 ? nameBytes : nameBytes.sublist(0, end));
      saves.add(Ps1CardSave(name, nameBytes, blocks));
    }
    return Ps1MemoryCard._(Uint8List.fromList(bytes), saves);
  }

  /// A freshly formatted card holding only the saves [belongs] accepts,
  /// packed from block 1 in their current order. The same saves always give
  /// the same bytes, whatever else was on this card or where they sat.
  Uint8List extract(bool Function(String name) belongs) {
    final out = formatted();
    var target = 1;
    for (final save in saves.where((s) => belongs(s.name))) {
      final placed = [for (var k = 0; k < save.blocks.length; k++) target + k];
      _writeSave(out, save, placed);
      target += save.blocks.length;
    }
    return out;
  }

  /// This card with the saves [belongs] accepts replaced by those on
  /// [incoming] (its other saves ignored). The old ones are marked deleted,
  /// as the PS1 does; every other save keeps its blocks and bytes. New saves
  /// take the lowest free blocks. Null when [incoming] has none of those
  /// saves (nothing to change). Throws [Ps1CardFullException] when they
  /// don't fit.
  Uint8List? replaceSaves(Ps1MemoryCard incoming, bool Function(String name) belongs) {
    final wanted = incoming.saves.where((s) => belongs(s.name)).toList();
    if (wanted.isEmpty) return null;
    final out = Uint8List.fromList(_bytes);
    for (final save in saves.where((s) => belongs(s.name))) {
      for (final block in save.blocks) {
        final entry = _entry(out, block);
        entry[0] = (_state(out, block) & 0x0F) | 0xA0; // 0x51/52/53 → deleted 0xA1/A2/A3
        _checksum(entry);
      }
    }
    final free = _freeBlockList(out);
    final needed = wanted.fold<int>(0, (n, s) => n + s.blocks.length);
    if (needed > free.length) throw Ps1CardFullException(needed, free.length);
    var used = 0;
    for (final save in wanted) {
      final placed = free.sublist(used, used + save.blocks.length);
      incoming._copyBlocks(out, save, placed);
      _writeSaveEntries(out, save, placed);
      used += save.blocks.length;
    }
    return out;
  }

  /// A card as DuckStation formats one: `MC` header, all 15 directory
  /// entries free, an empty broken-sector list, zeroed spare frames, the
  /// write-test frame a copy of the header, and blocks filled with 0xFF.
  static Uint8List formatted() {
    final card = Uint8List(size)..fillRange(_blockSize, size, 0xFF);
    final header = _frame(card, 0)
      ..[0] = 0x4D
      ..[1] = 0x43;
    _checksum(header);
    for (var i = 1; i <= _dataBlocks; i++) {
      final entry = _frame(card, i)
        ..[0] = _free
        ..[8] = 0xFF
        ..[9] = 0xFF;
      _checksum(entry);
    }
    for (var i = 16; i < 36; i++) {
      final entry = _frame(card, i)..fillRange(0, 4, 0xFF);
      entry[8] = 0xFF;
      entry[9] = 0xFF;
      _checksum(entry);
    }
    _frame(card, 63).setAll(0, header);
    return card;
  }

  void _writeSave(Uint8List out, Ps1CardSave save, List<int> placed) {
    _copyBlocks(out, save, placed);
    _writeSaveEntries(out, save, placed);
  }

  void _copyBlocks(Uint8List out, Ps1CardSave save, List<int> placed) {
    for (var k = 0; k < placed.length; k++) {
      final from = save.blocks[k] * _blockSize;
      out.setRange(placed[k] * _blockSize, placed[k] * _blockSize + _blockSize, _bytes, from);
    }
  }

  static void _writeSaveEntries(Uint8List out, Ps1CardSave save, List<int> placed) {
    for (var k = 0; k < placed.length; k++) {
      final last = k == placed.length - 1;
      final entry = _entry(out, placed[k])..fillRange(0, _frameSize, 0);
      ByteData.sublistView(entry)
        ..setUint32(0, k == 0 ? _inUseFirst : (last ? _inUseLast : _inUseMiddle), Endian.little)
        ..setUint32(4, k == 0 ? placed.length * _blockSize : 0, Endian.little)
        ..setUint16(8, last ? 0xFFFF : placed[k + 1] - 1, Endian.little);
      if (k == 0) entry.setAll(0x0A, save.nameBytes);
      _checksum(entry);
    }
  }

  static List<int> _freeBlockList(Uint8List bytes) => [
        for (var block = 1; block <= _dataBlocks; block++)
          if (_state(bytes, block) & 0xF0 == 0xA0) block,
      ];

  static Uint8List _frame(Uint8List card, int n) =>
      Uint8List.sublistView(card, n * _frameSize, n * _frameSize + _frameSize);
  static Uint8List _entry(Uint8List card, int block) => _frame(card, block);
  static int _state(Uint8List card, int block) =>
      ByteData.sublistView(card, block * _frameSize).getUint32(0, Endian.little);
  static int _next(Uint8List card, int block) =>
      ByteData.sublistView(card, block * _frameSize).getUint16(8, Endian.little);
  static void _checksum(Uint8List frame) {
    var x = 0;
    for (var i = 0; i < _frameSize - 1; i++) {
      x ^= frame[i];
    }
    frame[_frameSize - 1] = x;
  }
}
