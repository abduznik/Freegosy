import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:freegosy/core/save/strategies/pcsx2_state_file.dart';

/// A `.p2s`-shaped zip like PCSX2 writes: the version entry first (stored
/// uncompressed: u32 LE format id + NUL-terminated build string, 36 bytes),
/// then a payload, then optionally `Screenshot.png`.
Uint8List buildP2s({
  String? version = 'v2.8.2',
  int formatId = 0x9A590000,
  List<int>? screenshot,
  bool storedVersionEntry = true,
}) {
  final archive = Archive();
  if (version != null) {
    final data = ByteData(36)..setUint32(0, formatId, Endian.little);
    final bytes = data.buffer.asUint8List();
    bytes.setRange(4, 4 + version.length, version.codeUnits);
    archive.add(ArchiveFile.bytes(Pcsx2StateFile.versionEntryName, bytes)
      ..compression = storedVersionEntry ? CompressionType.none : CompressionType.deflate);
  }
  archive.add(ArchiveFile.bytes('eeMemory.bin', List.filled(4096, 7)));
  if (screenshot != null) {
    archive.add(ArchiveFile.bytes(Pcsx2StateFile.screenshotEntryName, screenshot));
  }
  return ZipEncoder().encodeBytes(archive);
}
