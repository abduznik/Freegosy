import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

// RomM's `content_hash` for a save, computed the way RomM computes it
// (backend/handler/filesystem/assets_handler.py, rommapp/romm 5b3d0bf), so a
// save on this PC can be compared with RomM's without downloading it.

/// A plain save file: the md5 of its bytes.
String rommHashOfFile(Uint8List bytes) => md5.convert(bytes).toString();

/// A zip's files as (name inside the zip, md5 of the file) in zip order:
/// the md5 of their `name:md5` lines sorted by name, joined with a newline. Like
/// RomM's Python `sorted(namelist())`, the sort is stable, so two files of
/// one name both count, in their zip order. Folder entries (a trailing `/`)
/// are skipped.
String rommHashOfDigests(List<(String, String)> files) {
  final kept = [for (final f in files) if (!f.$1.endsWith('/')) f];
  // List.sort isn't stable: order by name, then by position.
  final order = List.generate(kept.length, (i) => i)
    ..sort((a, b) {
      final byName = kept[a].$1.compareTo(kept[b].$1);
      return byName != 0 ? byName : a.compareTo(b);
    });
  final lines = [for (final i in order) '${kept[i].$1}:${kept[i].$2}'];
  return md5.convert(utf8.encode(lines.join('\n'))).toString();
}

/// The md5 of [file], read as a stream (a save can be large).
Future<String> md5OfFile(io.File file) async => (await md5.bind(file.openRead()).first).toString();

/// A zip's files ([entries]: name inside the zip → bytes): the md5 of
/// `<name>:<md5 of the file>` lines, sorted by name, joined with "\n".
String rommHashOfZipEntries(Map<String, Uint8List> entries) =>
    rommHashOfDigests([for (final e in entries.entries) (e.key, md5.convert(e.value).toString())]);

/// The hash RomM gives an uploaded file: a zip by its contents (folders
/// skipped; every entry, two of one name too, as Python's `namelist()`
/// lists them), anything else by its bytes; null when a zip can't be read.
String? rommHashOfUpload(Uint8List bytes) {
  if (!looksLikeZip(bytes)) return rommHashOfFile(bytes);
  try {
    // Not ZipDecoder: its Archive keeps one entry per name.
    return _hashZipEntries(ZipDirectory()..read(InputMemoryStream(bytes)));
  } catch (_) {
    return null;
  }
}

/// Whether [bytes] are a zip as Python's `zipfile.is_zipfile` (RomM) sees
/// it: an end-of-central-directory record ("PK", 5, 6) in the last 22
/// bytes, or within the 64 KB comment before them.
bool looksLikeZip(Uint8List bytes) => _hasEndRecord(bytes);

/// [looksLikeZip] for a file on disk, reading only its tail.
Future<bool> fileLooksLikeZip(io.File file) async {
  final raf = await file.open();
  try {
    final length = await raf.length();
    final tail = length < _endRecordSearch ? length : _endRecordSearch;
    await raf.setPosition(length - tail);
    return _hasEndRecord(await raf.read(tail));
  } finally {
    await raf.close();
  }
}

/// The content_hash RomM gives [file] when uploaded: a zip by its contents
/// (read from the file, one entry at a time), anything else by its bytes,
/// streamed; null when a zip can't be read.
Future<String?> rommHashOfSaveFile(io.File file) async {
  if (!await fileLooksLikeZip(file)) return md5OfFile(file);
  final input = InputFileStream(file.path);
  try {
    return _hashZipEntries(ZipDirectory()..read(input));
  } catch (_) {
    return null;
  } finally {
    await input.close();
  }
}

String _hashZipEntries(ZipDirectory directory) {
  // An end record promising entries that aren't there: Python still calls
  // it a zip, but RomM can't open it and stores no hash. So no hash here.
  if (directory.fileHeaders.length != directory.totalCentralDirectoryEntries) {
    throw const FormatException('the zip lists fewer entries than its end record says');
  }
  final files = <(String, String)>[];
  for (final header in directory.fileHeaders) {
    final zip = header.file!;
    if (zip.filename.endsWith('/')) continue;
    final entry = ArchiveFile.file(zip.filename, zip.uncompressedSize, zip)..compression = zip.compressionMethod;
    files.add((zip.filename, md5.convert(entry.content).toString()));
  }
  return rommHashOfDigests(files);
}

const _endRecordSize = 22;
const _endRecordSearch = _endRecordSize + 0xFFFF;

bool _hasEndRecord(List<int> b) {
  if (b.length < _endRecordSize) return false;
  bool sigAt(int i) => b[i] == 0x50 && b[i + 1] == 0x4B && b[i + 2] == 5 && b[i + 3] == 6;
  // Most zips: no comment, the record is the last 22 bytes.
  final last = b.length - _endRecordSize;
  if (sigAt(last) && b[last + 20] == 0 && b[last + 21] == 0) return true;
  // Else, as Python: the last marker within the comment's reach decides,
  // and it needs a whole record after it.
  final start = b.length > _endRecordSearch ? b.length - _endRecordSearch : 0;
  for (var i = b.length - 4; i >= start; i--) {
    if (sigAt(i)) return b.length - i >= _endRecordSize;
  }
  return false;
}
