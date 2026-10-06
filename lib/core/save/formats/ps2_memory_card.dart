import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// A file inside a save on a PS2 memory card, with its directory-entry
/// metadata: the mode flags, the attribute word, and the created/modified
/// times as the card's 8-byte time records (kept as-is, so a save moves
/// between cards unchanged).
class Ps2CardFile {
  Ps2CardFile({
    required this.name,
    required this.data,
    this.mode = Ps2MemoryCard.fileMode,
    this.attr = 0,
    Uint8List? created,
    Uint8List? modified,
  })  : created = created ?? Ps2MemoryCard.timeRecord(DateTime.now()),
        modified = modified ?? Ps2MemoryCard.timeRecord(DateTime.now());

  final String name;
  final Uint8List data;
  final int mode;
  final int attr;
  final Uint8List created;
  final Uint8List modified;
}

/// A save on a PS2 memory card: a top-level directory (e.g. `BASLUS-20502`,
/// region prefix + product code + a suffix the game chooses) and its files.
class Ps2CardSave {
  Ps2CardSave({
    required this.name,
    required this.files,
    this.mode = Ps2MemoryCard.dirMode,
    this.attr = 0,
    Uint8List? created,
    Uint8List? modified,
  })  : created = created ?? Ps2MemoryCard.timeRecord(DateTime.now()),
        modified = modified ?? Ps2MemoryCard.timeRecord(DateTime.now());

  final String name;
  final List<Ps2CardFile> files;
  final int mode;
  final int attr;
  final Uint8List created;
  final Uint8List modified;
}

/// Thrown by [Ps2MemoryCard.withSaves] when the saves don't fit on the card.
class Ps2CardFullException implements Exception {
  Ps2CardFullException(this.needed, this.capacity);

  /// Clusters of 1 KB the saves and their directories need, and the card has.
  final int needed;
  final int capacity;

  @override
  String toString() => 'Ps2CardFullException: $needed clusters needed, the card has $capacity';
}

/// A PS2 memory card image as PCSX2 and LRPS2 store a "file" card: 8 MB of
/// 512-byte pages, each followed by 16 bytes of ECC (8,650,752 bytes), or
/// without the ECC (8,388,608 bytes).
///
/// The card holds a small FAT file system:
/// - page 0 is the superblock (`Sony PS2 Memory Card Format`), giving the
///   geometry, the indirect FAT clusters and where the allocatable clusters
///   start;
/// - the FAT (reached through the indirect FAT clusters) links the 1 KB
///   clusters of each file and directory;
/// - a directory is a list of 512-byte entries (mode, length, times, first
///   cluster, name); the root holds one directory per save.
///
/// Used to sync one game's saves out of, and back into, a card shared by
/// every game, without touching the other games' saves. Only saves made of
/// plain files are supported, which is how the PS2 stores them; a card with
/// anything else is refused rather than changed.
class Ps2MemoryCard {
  Ps2MemoryCard._(this._bytes, this._ecc, this._geometry, this._rootDot, this._rootDotDot, this.saves);

  static const sizeWithEcc = _pages * (_pageSize + _spareSize);
  static const sizeWithoutEcc = _pages * _pageSize;

  static const _pageSize = 512;
  static const _spareSize = 16;
  static const _pages = 16384;
  static const _pagesPerCluster = 2;
  static const _pagesPerBlock = 16;
  static const _clusterSize = _pageSize * _pagesPerCluster;
  static const _entrySize = 512;
  static const _entriesPerCluster = _clusterSize ~/ _entrySize;
  static const _fatPerCluster = _clusterSize ~/ 4;
  static const _magic = 'Sony PS2 Memory Card Format ';

  static const _chainEnd = 0xFFFFFFFF;
  static const _free = 0x7FFFFFFF;
  static const _allocated = 0x80000000;

  static const _exists = 0x8000;
  static const _isDir = 0x0020;
  static const _isFile = 0x0010;

  /// Mode of a save directory the PS2 creates: read/write/execute, directory,
  /// the 0x0400 flag every entry carries, exists.
  static const dirMode = 0x8427;

  /// Mode of a file the PS2 creates.
  static const fileMode = 0x8417;

  final Uint8List _bytes;
  final bool _ecc;
  final _Geometry _geometry;
  final Uint8List _rootDot;
  final Uint8List _rootDotDot;

  /// The saves on the card, in directory order.
  final List<Ps2CardSave> saves;

  /// Allocatable clusters not used by any file or directory.
  int get freeClusters => _geometry.allocEnd - _clustersNeeded(saves);

  /// A quick check that [bytes] is a formatted PS2 card of a supported size.
  static bool looksLikeCard(Uint8List bytes) =>
      (bytes.length == sizeWithEcc || bytes.length == sizeWithoutEcc) &&
      latin1.decode(bytes.sublist(0, _magic.length), allowInvalid: true) == _magic;

  /// A card of a supported size that was never formatted: every byte `FF`,
  /// as PCSX2 and LRPS2 create a new card. The PS2 formats it on first save.
  static bool isUnformatted(Uint8List bytes) {
    if (bytes.length != sizeWithEcc && bytes.length != sizeWithoutEcc) return false;
    for (final b in bytes) {
      if (b != 0xFF) return false;
    }
    return true;
  }

  /// Reads and checks [bytes]: the size, the superblock, and every chain,
  /// directory and file the saves use. Throws [FormatException] for anything
  /// else, so a card that isn't understood is never changed.
  factory Ps2MemoryCard.parse(Uint8List bytes) {
    final ecc = switch (bytes.length) {
      sizeWithEcc => true,
      sizeWithoutEcc => false,
      _ => throw FormatException('expected $sizeWithEcc or $sizeWithoutEcc bytes, got ${bytes.length}'),
    };
    if (!looksLikeCard(bytes)) throw const FormatException('no PS2 memory card superblock');
    final reader = _Reader(bytes, ecc);
    final geometry = _Geometry.read(reader.page(0));
    reader.geometry = geometry;

    final rootFirst = reader.cluster(geometry.allocOffset + geometry.rootCluster);
    final rootDot = Uint8List.fromList(rootFirst.sublist(0, _entrySize));
    if (_name(rootDot) != '.' || !_isDirEntry(rootDot)) throw const FormatException('root directory damaged');
    final root = reader.directory(geometry.rootCluster, _u32(rootDot, 4));
    if (root.length < 2 || _name(root[1]) != '..') throw const FormatException('root directory damaged');

    final saves = <Ps2CardSave>[];
    for (final entry in root.skip(2)) {
      if (_u16(entry, 0) & _exists == 0) continue;
      final name = _name(entry);
      if (!_isDirEntry(entry)) throw FormatException('unsupported file in the card root: $name');
      final dir = reader.directory(_u32(entry, 0x10), _u32(entry, 4));
      if (dir.length < 2 || _name(dir[0]) != '.' || _name(dir[1]) != '..') {
        throw FormatException('save directory damaged: $name');
      }
      final files = <Ps2CardFile>[];
      for (final f in dir.skip(2)) {
        final mode = _u16(f, 0);
        if (mode & _exists == 0) continue;
        if (mode & _isDir != 0 || mode & _isFile == 0) {
          throw FormatException('unsupported entry in save $name: ${_name(f)}');
        }
        files.add(Ps2CardFile(
          name: _name(f),
          data: reader.file(_u32(f, 0x10), _u32(f, 4)),
          mode: mode,
          attr: _u32(f, 0x20),
          created: Uint8List.fromList(f.sublist(8, 16)),
          modified: Uint8List.fromList(f.sublist(0x18, 0x20)),
        ));
      }
      saves.add(Ps2CardSave(
        name: name,
        files: files,
        mode: _u16(entry, 0),
        attr: _u32(entry, 0x20),
        created: Uint8List.fromList(entry.sublist(8, 16)),
        modified: Uint8List.fromList(entry.sublist(0x18, 0x20)),
      ));
    }
    return Ps2MemoryCard._(
        Uint8List.fromList(bytes), ecc, geometry, rootDot, Uint8List.fromList(root[1]), saves);
  }

  /// A newly formatted, empty card, laid out as the PS2 formats one.
  static Uint8List formatted({bool ecc = true, DateTime? now}) {
    final raw = ecc ? _pageSize + _spareSize : _pageSize;
    final bytes = Uint8List(_pages * raw);
    final geometry = _Geometry.standard();
    final writer = _Writer(bytes, ecc);
    for (var n = 0; n < _pages; n++) {
      writer.page(n, Uint8List(_pageSize));
    }
    writer.page(0, geometry.superblock());
    final ifc = Uint8List(_clusterSize);
    for (var i = 0; i < _fatPerCluster; i++) {
      _setU32(ifc, i * 4, i < geometry.fatClusters ? geometry.firstFatCluster + i : _chainEnd);
    }
    writer.cluster(geometry.ifcList[0], ifc);
    // FAT entries past the last allocatable cluster read as chain ends;
    // _build writes the others.
    final endMarks = Uint8List(_clusterSize)..fillRange(0, _clusterSize, 0xFF);
    for (var i = 0; i < geometry.fatClusters; i++) {
      writer.cluster(geometry.firstFatCluster + i, endMarks);
    }
    // The second backup block is erased: nothing to recover.
    final block = geometry.goodBlock2 * _pagesPerBlock * raw;
    bytes.fillRange(block, block + _pagesPerBlock * raw, 0xFF);

    final time = timeRecord(now ?? DateTime.now());
    final dot = _entry(mode: dirMode, length: 2, cluster: 0, created: time, modified: time, name: '.');
    final dotDot = _entry(mode: 0xA426, length: 0, cluster: 0, created: time, modified: time, name: '..');
    return _build(bytes, ecc, geometry, dot, dotDot, const []);
  }

  /// This card with every save [belongs] accepts replaced by [incoming]; all
  /// other saves keep their files and metadata. Everything outside the FAT
  /// and the allocatable clusters (superblock, backup blocks) stays byte for
  /// byte. Throws [Ps2CardFullException] when the saves don't fit.
  Uint8List withSaves(List<Ps2CardSave> incoming, bool Function(String name) belongs) {
    final names = {for (final s in incoming) s.name};
    final kept = [
      for (final s in saves)
        if (!belongs(s.name) && !names.contains(s.name)) s,
    ];
    return _build(Uint8List.fromList(_bytes), _ecc, _geometry, _rootDot, _rootDotDot, [...kept, ...incoming]);
  }

  /// A PS2 time record for [time]: the card keeps Japan time (UTC+9).
  static Uint8List timeRecord(DateTime time) {
    final t = time.toUtc().add(const Duration(hours: 9));
    final r = Uint8List(8);
    r[1] = t.second;
    r[2] = t.minute;
    r[3] = t.hour;
    r[4] = t.day;
    r[5] = t.month;
    r[6] = t.year & 0xFF;
    r[7] = t.year >> 8;
    return r;
  }

  // ─── writing ──────────────────────────────────────────────────────────

  static int _clustersNeeded(List<Ps2CardSave> saves) {
    var n = _ceil(2 + saves.length, _entriesPerCluster);
    for (final s in saves) {
      n += _ceil(2 + s.files.length, _entriesPerCluster);
      for (final f in s.files) {
        n += _ceil(f.data.length, _clusterSize);
      }
    }
    return n;
  }

  /// Writes the root directory, [saves] and a matching FAT into [bytes],
  /// packed from the first allocatable cluster.
  static Uint8List _build(Uint8List bytes, bool ecc, _Geometry g, Uint8List rootDot, Uint8List rootDotDot,
      List<Ps2CardSave> saves) {
    final needed = _clustersNeeded(saves);
    if (needed > g.allocEnd) throw Ps2CardFullException(needed, g.allocEnd);

    final fat = List<int>.filled(g.allocEnd, _free);
    final data = <int, Uint8List>{};
    var next = 0;

    /// Allocates a chain of [count] clusters and returns them.
    List<int> chain(int count) {
      final clusters = [for (var i = 0; i < count; i++) next + i];
      next += count;
      for (var i = 0; i < count; i++) {
        fat[clusters[i]] = i == count - 1 ? _chainEnd : _allocated | clusters[i + 1];
      }
      return clusters;
    }

    void writeEntries(List<int> clusters, List<Uint8List> entries) {
      for (var i = 0; i < clusters.length; i++) {
        final c = Uint8List(_clusterSize);
        for (var j = 0; j < _entriesPerCluster; j++) {
          final k = i * _entriesPerCluster + j;
          if (k < entries.length) c.setRange(j * _entrySize, (j + 1) * _entrySize, entries[k]);
        }
        data[clusters[i]] = c;
      }
    }

    final rootClusters = chain(_ceil(2 + saves.length, _entriesPerCluster));
    final rootEntries = <Uint8List>[
      _withField(rootDot, length: 2 + saves.length, cluster: rootClusters.first),
      Uint8List.fromList(rootDotDot),
    ];
    for (var i = 0; i < saves.length; i++) {
      final save = saves[i];
      final dirClusters = chain(_ceil(2 + save.files.length, _entriesPerCluster));
      final entries = <Uint8List>[
        _entry(mode: dirMode, length: 0, cluster: rootClusters.first, dirEntry: 2 + i,
            created: save.created, modified: save.modified, name: '.'),
        _entry(mode: dirMode, length: 0, cluster: 0, created: save.created, modified: save.modified, name: '..'),
      ];
      for (final file in save.files) {
        final fileClusters = chain(_ceil(file.data.length, _clusterSize));
        for (var k = 0; k < fileClusters.length; k++) {
          final c = Uint8List(_clusterSize);
          final start = k * _clusterSize;
          final end = start + _clusterSize < file.data.length ? start + _clusterSize : file.data.length;
          c.setRange(0, end - start, file.data, start);
          data[fileClusters[k]] = c;
        }
        entries.add(_entry(
          mode: file.mode,
          length: file.data.length,
          cluster: fileClusters.isEmpty ? _chainEnd : fileClusters.first,
          attr: file.attr,
          created: file.created,
          modified: file.modified,
          name: file.name,
        ));
      }
      writeEntries(dirClusters, entries);
      rootEntries.add(_entry(
        mode: save.mode,
        length: entries.length,
        cluster: dirClusters.first,
        attr: save.attr,
        created: save.created,
        modified: save.modified,
        name: save.name,
      ));
    }
    writeEntries(rootClusters, rootEntries);

    final writer = _Writer(bytes, ecc);
    if (g.rootCluster != 0) {
      // The root is rebuilt at the first allocatable cluster.
      g = g.withRootAtStart();
      writer.page(0, g.superblockOver(_Reader(bytes, ecc).page(0)));
    }
    final empty = Uint8List(_clusterSize);
    for (var c = 0; c < g.allocEnd; c++) {
      writer.cluster(g.allocOffset + c, data[c] ?? empty);
    }
    // The FAT: rewrite the entries of the allocatable clusters, keep the rest.
    final reader = _Reader(bytes, ecc)..geometry = g;
    for (var fc = 0; fc * _fatPerCluster < g.allocEnd; fc++) {
      final at = reader.fatCluster(fc);
      final cluster = reader.cluster(at);
      for (var i = 0; i < _fatPerCluster; i++) {
        final n = fc * _fatPerCluster + i;
        if (n < g.allocEnd) _setU32(cluster, i * 4, fat[n]);
      }
      writer.cluster(at, cluster);
    }
    return bytes;
  }

  static Uint8List _entry({
    required int mode,
    required int length,
    required int cluster,
    int dirEntry = 0,
    int attr = 0,
    required Uint8List created,
    required Uint8List modified,
    required String name,
  }) {
    final e = Uint8List(_entrySize);
    _setU16(e, 0, mode);
    _setU32(e, 4, length);
    e.setRange(8, 16, created);
    _setU32(e, 0x10, cluster);
    _setU32(e, 0x14, dirEntry);
    e.setRange(0x18, 0x20, modified);
    _setU32(e, 0x20, attr);
    final n = latin1.encode(name);
    if (n.isEmpty || n.length > 32) throw ArgumentError.value(name, 'name', 'must be 1-32 characters');
    e.setRange(0x40, 0x40 + n.length, n);
    return e;
  }

  static Uint8List _withField(Uint8List entry, {required int length, required int cluster}) {
    final e = Uint8List.fromList(entry);
    _setU32(e, 4, length);
    _setU32(e, 0x10, cluster);
    return e;
  }

  // ─── helpers ──────────────────────────────────────────────────────────

  static int _ceil(int a, int b) => (a + b - 1) ~/ b;
  static int _u16(Uint8List b, int o) => b[o] | b[o + 1] << 8;
  static int _u32(Uint8List b, int o) => b[o] | b[o + 1] << 8 | b[o + 2] << 16 | b[o + 3] << 24;
  static void _setU16(Uint8List b, int o, int v) {
    b[o] = v & 0xFF;
    b[o + 1] = v >> 8 & 0xFF;
  }

  static void _setU32(Uint8List b, int o, int v) {
    for (var i = 0; i < 4; i++) {
      b[o + i] = v >> (8 * i) & 0xFF;
    }
  }

  static bool _isDirEntry(Uint8List e) => _u16(e, 0) & (_exists | _isDir | _isFile) == (_exists | _isDir);

  static String _name(Uint8List e) {
    final raw = e.sublist(0x40, 0x60);
    final end = raw.indexOf(0);
    return latin1.decode(end < 0 ? raw : raw.sublist(0, end));
  }

  // ECC: a Hamming code of 3 bytes per 128-byte chunk of a page, stored in
  // the page's 16 spare bytes after the data (12 bytes of ECC, 4 zero).
  static final _parity = List<int>.generate(256, (b) {
    var p = 0;
    for (var x = b; x != 0; x >>= 1) {
      p ^= x & 1;
    }
    return p;
  });
  static final _columnMasks = List<int>.generate(256, (b) {
    const masks = [0x55, 0x33, 0x0F, 0x00, 0xAA, 0xCC, 0xF0];
    var m = 0;
    for (var i = 0; i < masks.length; i++) {
      m |= _parity[b & masks[i]] << i;
    }
    return m;
  });

  static Uint8List _spare(Uint8List page) {
    final spare = Uint8List(_spareSize);
    for (var chunk = 0; chunk < _pageSize ~/ 128; chunk++) {
      var column = 0x77, line0 = 0x7F, line1 = 0x7F;
      for (var i = 0; i < 128; i++) {
        final b = page[chunk * 128 + i];
        column ^= _columnMasks[b];
        if (_parity[b] == 1) {
          line0 ^= ~i;
          line1 ^= i;
        }
      }
      spare[chunk * 3] = column & 0xFF;
      spare[chunk * 3 + 1] = line0 & 0x7F;
      spare[chunk * 3 + 2] = line1 & 0x7F;
    }
    return spare;
  }

  /// The spare bytes (ECC) stored after the 512-byte [page] on the card.
  @visibleForTesting
  static Uint8List eccOf(Uint8List page) => _spare(page);
}

class _Geometry {
  _Geometry({
    required this.clustersPerCard,
    required this.allocOffset,
    required this.allocEnd,
    required this.rootCluster,
    required this.goodBlock1,
    required this.goodBlock2,
    required this.ifcList,
  });

  factory _Geometry.read(Uint8List p) {
    int u16(int o) => Ps2MemoryCard._u16(p, o);
    int u32(int o) => Ps2MemoryCard._u32(p, o);
    final version = latin1.decode(p.sublist(0x1C, 0x28)).split('\u0000').first;
    if (!version.startsWith('1.')) throw FormatException('unsupported card format version $version');
    if (u16(0x28) != Ps2MemoryCard._pageSize ||
        u16(0x2A) != Ps2MemoryCard._pagesPerCluster ||
        u16(0x2C) != Ps2MemoryCard._pagesPerBlock) {
      throw const FormatException('unsupported card geometry');
    }
    final g = _Geometry(
      clustersPerCard: u32(0x30),
      allocOffset: u32(0x34),
      allocEnd: u32(0x38),
      rootCluster: u32(0x3C),
      goodBlock1: u32(0x40),
      goodBlock2: u32(0x44),
      ifcList: [for (var i = 0; i < 32; i++) u32(0x50 + i * 4)],
    );
    if (g.clustersPerCard != Ps2MemoryCard._pages ~/ Ps2MemoryCard._pagesPerCluster ||
        g.allocEnd == 0 ||
        g.allocOffset + g.allocEnd > g.clustersPerCard ||
        g.rootCluster >= g.allocEnd) {
      throw const FormatException('superblock damaged');
    }
    return g;
  }

  /// The layout the PS2 gives an 8 MB card.
  factory _Geometry.standard() {
    const clusters = Ps2MemoryCard._pages ~/ Ps2MemoryCard._pagesPerCluster;
    const firstIfc = 0x2000 ~/ Ps2MemoryCard._clusterSize;
    const epc = Ps2MemoryCard._fatPerCluster;
    const fatClusters = (clusters - (firstIfc + 2) + epc - 1) ~/ epc;
    const allocOffset = firstIfc + 1 + fatClusters;
    const blocks = Ps2MemoryCard._pages ~/ Ps2MemoryCard._pagesPerBlock;
    const clustersPerBlock = Ps2MemoryCard._pagesPerBlock ~/ Ps2MemoryCard._pagesPerCluster;
    return _Geometry(
      clustersPerCard: clusters,
      allocOffset: allocOffset,
      allocEnd: (blocks - 2) * clustersPerBlock - allocOffset,
      rootCluster: 0,
      goodBlock1: blocks - 1,
      goodBlock2: blocks - 2,
      ifcList: [firstIfc, for (var i = 1; i < 32; i++) 0],
    );
  }

  final int clustersPerCard;
  final int allocOffset;
  final int allocEnd;
  final int rootCluster;
  final int goodBlock1;
  final int goodBlock2;
  final List<int> ifcList;

  int get firstFatCluster => ifcList[0] + 1;

  _Geometry withRootAtStart() => _Geometry(
        clustersPerCard: clustersPerCard,
        allocOffset: allocOffset,
        allocEnd: allocEnd,
        rootCluster: 0,
        goodBlock1: goodBlock1,
        goodBlock2: goodBlock2,
        ifcList: ifcList,
      );
  int get fatClusters => (allocEnd + Ps2MemoryCard._fatPerCluster - 1) ~/ Ps2MemoryCard._fatPerCluster;

  Uint8List superblock() {
    final p = Uint8List(Ps2MemoryCard._pageSize);
    p.setRange(0, 28, latin1.encode(Ps2MemoryCard._magic));
    p.setRange(0x1C, 0x1C + 7, latin1.encode('1.2.0.0'));
    Ps2MemoryCard._setU16(p, 0x28, Ps2MemoryCard._pageSize);
    Ps2MemoryCard._setU16(p, 0x2A, Ps2MemoryCard._pagesPerCluster);
    Ps2MemoryCard._setU16(p, 0x2C, Ps2MemoryCard._pagesPerBlock);
    Ps2MemoryCard._setU16(p, 0x2E, 0xFF00);
    for (var i = 0; i < 32; i++) {
      Ps2MemoryCard._setU32(p, 0xD0 + i * 4, 0xFFFFFFFF);
    }
    p[0x150] = 2; // card type: PS2
    p[0x151] = 0x2B; // flags, as the PS2 formats a card
    return superblockOver(p);
  }

  /// [page] (a superblock) with this geometry's fields written in.
  Uint8List superblockOver(Uint8List page) {
    final p = Uint8List.fromList(page);
    Ps2MemoryCard._setU32(p, 0x30, clustersPerCard);
    Ps2MemoryCard._setU32(p, 0x34, allocOffset);
    Ps2MemoryCard._setU32(p, 0x38, allocEnd);
    Ps2MemoryCard._setU32(p, 0x3C, rootCluster);
    Ps2MemoryCard._setU32(p, 0x40, goodBlock1);
    Ps2MemoryCard._setU32(p, 0x44, goodBlock2);
    for (var i = 0; i < 32; i++) {
      Ps2MemoryCard._setU32(p, 0x50 + i * 4, ifcList[i]);
    }
    return p;
  }
}

class _Reader {
  _Reader(this.bytes, this.ecc);

  final Uint8List bytes;
  final bool ecc;
  late _Geometry geometry;

  int get _raw => ecc ? Ps2MemoryCard._pageSize + Ps2MemoryCard._spareSize : Ps2MemoryCard._pageSize;

  Uint8List page(int n) => Uint8List.sublistView(bytes, n * _raw, n * _raw + Ps2MemoryCard._pageSize);

  Uint8List cluster(int n) {
    if (n < 0 || n >= geometry.clustersPerCard) throw FormatException('cluster $n out of range');
    final out = Uint8List(Ps2MemoryCard._clusterSize);
    for (var i = 0; i < Ps2MemoryCard._pagesPerCluster; i++) {
      out.setRange(i * Ps2MemoryCard._pageSize, (i + 1) * Ps2MemoryCard._pageSize,
          page(n * Ps2MemoryCard._pagesPerCluster + i));
    }
    return out;
  }

  /// The absolute cluster holding FAT cluster number [fc].
  int fatCluster(int fc) {
    const epc = Ps2MemoryCard._fatPerCluster;
    final ifc = geometry.ifcList[fc ~/ epc];
    return Ps2MemoryCard._u32(cluster(ifc), (fc % epc) * 4);
  }

  final _fatCache = <int, Uint8List>{};

  int fat(int n) {
    if (n < 0 || n >= geometry.allocEnd) throw FormatException('FAT index $n out of range');
    const epc = Ps2MemoryCard._fatPerCluster;
    final c = _fatCache.putIfAbsent(n ~/ epc, () => cluster(fatCluster(n ~/ epc)));
    return Ps2MemoryCard._u32(c, (n % epc) * 4);
  }

  /// The allocatable clusters of the chain starting at [first], checked for
  /// loops, free clusters and out-of-range links.
  List<int> chain(int first, int maxLength) {
    final out = <int>[];
    final seen = <int>{};
    var c = first;
    while (true) {
      if (!seen.add(c)) throw const FormatException('cluster chain loops');
      if (out.length >= maxLength) throw const FormatException('cluster chain longer than its file');
      out.add(c);
      final e = fat(c);
      if (e == Ps2MemoryCard._chainEnd) return out;
      if (e & Ps2MemoryCard._allocated == 0) throw const FormatException('cluster chain runs into a free cluster');
      c = e & 0x7FFFFFFF;
    }
  }

  Uint8List file(int first, int length) {
    if (length == 0) return Uint8List(0);
    final count = Ps2MemoryCard._ceil(length, Ps2MemoryCard._clusterSize);
    final clusters = chain(first, count);
    if (clusters.length != count) throw const FormatException('file shorter than its length');
    final out = Uint8List(count * Ps2MemoryCard._clusterSize);
    for (var i = 0; i < count; i++) {
      out.setRange(i * Ps2MemoryCard._clusterSize, (i + 1) * Ps2MemoryCard._clusterSize,
          cluster(geometry.allocOffset + clusters[i]));
    }
    return Uint8List.sublistView(out, 0, length);
  }

  List<Uint8List> directory(int first, int count) {
    if (count < 2 || count > 0xFFFF) throw FormatException('directory of $count entries');
    final data = file(first, count * Ps2MemoryCard._entrySize);
    return [
      for (var i = 0; i < count; i++)
        Uint8List.sublistView(data, i * Ps2MemoryCard._entrySize, (i + 1) * Ps2MemoryCard._entrySize),
    ];
  }
}

class _Writer {
  _Writer(this.bytes, this.ecc);

  final Uint8List bytes;
  final bool ecc;

  int get _raw => ecc ? Ps2MemoryCard._pageSize + Ps2MemoryCard._spareSize : Ps2MemoryCard._pageSize;

  void page(int n, Uint8List data) {
    final at = n * _raw;
    bytes.setRange(at, at + Ps2MemoryCard._pageSize, data);
    if (ecc) {
      bytes.setRange(at + Ps2MemoryCard._pageSize, at + _raw, Ps2MemoryCard._spare(data));
    }
  }

  void cluster(int n, Uint8List data) {
    for (var i = 0; i < Ps2MemoryCard._pagesPerCluster; i++) {
      page(n * Ps2MemoryCard._pagesPerCluster + i,
          Uint8List.sublistView(data, i * Ps2MemoryCard._pageSize, (i + 1) * Ps2MemoryCard._pageSize));
    }
  }
}
