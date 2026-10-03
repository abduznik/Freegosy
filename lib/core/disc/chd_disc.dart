import 'dart:convert';
import 'dart:typed_data';

import 'chd_reader.dart';

/// The text of SYSTEM.CNF, the boot file PlayStation and PlayStation 2
/// discs keep in the root directory of their ISO9660 file system, read from
/// [chd]; null when the disc has no ISO9660 volume or no SYSTEM.CNF.
Future<String?> readSystemCnf(ChdReader chd) async {
  final sectors = _Sectors(chd);
  if (!sectors.isDisc) return null;
  final volume = await sectors.read(16);
  if (volume[0] != 1 || ascii.decode(volume.sublist(1, 6), allowInvalid: true) != 'CD001') return null;
  final root = ByteData.sublistView(volume, 156);
  final rootLba = root.getUint32(2, Endian.little);
  final rootSectors = (root.getUint32(10, Endian.little) + 2047) ~/ 2048;

  for (var s = 0; s < rootSectors && s < 64; s++) {
    final directory = await sectors.read(rootLba + s);
    var pos = 0;
    while (pos + 33 < directory.length) {
      final length = directory[pos];
      if (length == 0) break; // the rest of this sector is padding
      final record = ByteData.sublistView(directory, pos, pos + length);
      final name = latin1.decode(directory.sublist(pos + 33, pos + 33 + directory[pos + 32]));
      if (name.split(';').first.toUpperCase() == 'SYSTEM.CNF') {
        final lba = record.getUint32(2, Endian.little);
        final size = record.getUint32(10, Endian.little);
        if (size > 64 * 1024) return null;
        final text = BytesBuilder();
        for (var i = 0; i * 2048 < size; i++) {
          text.add(await sectors.read(lba + i));
        }
        return latin1.decode(text.takeBytes().sublist(0, size));
      }
      pos += length;
    }
  }
  return null;
}

/// The 2048-byte user data of each sector: a DVD's sectors as they are; a
/// CD's from inside its raw frame (after the sync header, address and mode,
/// and for mode 2 the subheader).
class _Sectors {
  _Sectors(this._chd);
  final ChdReader _chd;

  static const _dvdSector = 2048, _cdFrame = 2448;

  bool get isDisc => _chd.unitBytes == _dvdSector || _chd.unitBytes == _cdFrame;

  Future<Uint8List> read(int lba) async {
    if (_chd.unitBytes == _dvdSector) return _chd.read(lba * _dvdSector, _dvdSector);
    final frame = await _chd.read(lba * _cdFrame, 2352);
    var dataStart = 0; // a cooked (2048-byte) track
    if (_hasSync(frame)) dataStart = frame[15] == 2 ? 24 : 16;
    return Uint8List.sublistView(frame, dataStart, dataStart + 2048);
  }

  static bool _hasSync(Uint8List frame) {
    if (frame[0] != 0 || frame[11] != 0) return false;
    for (var i = 1; i < 11; i++) {
      if (frame[i] != 0xFF) return false;
    }
    return true;
  }
}
