import 'dart:io' as io;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

/// Reads what a PCSX2 `.p2s` state (a zip archive) records about itself.
///
/// PCSX2 writes `PCSX2 Savestate Version.id` as the first entry, stored
/// uncompressed: a u32 (little endian) format id, then the NUL-terminated
/// build string (e.g. `v2.8.2`). So the version is readable from the first
/// few hundred bytes without unzipping the ~20 MB state.
class Pcsx2StateFile {
  Pcsx2StateFile._();

  static const versionEntryName = 'PCSX2 Savestate Version.id';
  static const screenshotEntryName = 'Screenshot.png';
  static const int _headBytes = 512;

  /// The format id (as `0x9A590000`) and build string from the zip's first
  /// local file header, or null if [head] isn't that layout.
  static ({String formatId, String version})? parseVersionHeader(Uint8List head) {
    if (head.length < 30) return null;
    final data = ByteData.sublistView(head);
    if (data.getUint32(0, Endian.little) != 0x04034b50) return null;
    if (data.getUint16(8, Endian.little) != 0) return null; // stored only
    final size = data.getUint32(18, Endian.little);
    final nameLength = data.getUint16(26, Endian.little);
    final extraLength = data.getUint16(28, Endian.little);
    final nameEnd = 30 + nameLength;
    if (head.length < nameEnd) return null;
    if (String.fromCharCodes(head.sublist(30, nameEnd)) != versionEntryName) return null;
    final start = nameEnd + extraLength;
    final end = start + size;
    if (size < 5 || head.length < end) return null;
    final formatId = data.getUint32(start, Endian.little);
    final text = head.sublist(start + 4, end);
    final nul = text.indexOf(0);
    final version = String.fromCharCodes(nul < 0 ? text : text.sublist(0, nul)).trim();
    if (version.isEmpty) return null;
    return (
      formatId: '0x${formatId.toRadixString(16).toUpperCase().padLeft(8, '0')}',
      version: version,
    );
  }

  /// [parseVersionHeader] on the start of [file]; null on any failure.
  static Future<({String formatId, String version})?> readVersion(io.File file) async {
    io.RandomAccessFile? raf;
    try {
      raf = await file.open();
      return parseVersionHeader(await raf.read(_headBytes));
    } catch (e) {
      debugPrint('[PCSX2] cannot read state version of ${file.path}: $e');
      return null;
    } finally {
      await raf?.close();
    }
  }

  /// The embedded `Screenshot.png`, or null if absent or unreadable.
  static Future<Uint8List?> readScreenshot(io.File file) async {
    InputFileStream? input;
    try {
      input = InputFileStream(file.path);
      final entry = ZipDecoder().decodeStream(input).findFile(screenshotEntryName);
      return entry?.readBytes();
    } catch (e) {
      debugPrint('[PCSX2] cannot read screenshot of ${file.path}: $e');
      return null;
    } finally {
      input?.closeSync();
    }
  }
}
