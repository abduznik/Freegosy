import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'romm_content_hash.dart';

// Hashes of a save's files that depend only on names and contents, never on
// file times or the zip around them.

/// Hashes the logical content of [filesMap]'s keys (files and/or
/// directories, recursing into any directory) — the exact same set of
/// entries a bundle push zips up. Unlike hashing the assembled zip file
/// itself, this depends only on each entry's relative path and raw bytes,
/// never on filesystem metadata (mtimes) or container-format details, so
/// it's identical whenever the underlying save content is identical —
/// letting a push/pull compare it against a value recorded at another
/// time (or read back from another push) to detect "nothing changed".
Future<String> saveContentHash(Map<io.File, io.File?> filesMap) async {
  final entries = <MapEntry<String, io.File>>[];
  for (final file in filesMap.keys) {
    if (await io.FileSystemEntity.isDirectory(file.path)) {
      final dirName = p.basename(file.path);
      await for (final child in io.Directory(file.path).list(recursive: true)) {
        if (child is io.File) {
          final relative = p.join(dirName, p.relative(child.path, from: file.path));
          entries.add(MapEntry(relative.replaceAll('\\', '/'), child));
        }
      }
    } else {
      entries.add(MapEntry(p.basename(file.path), file));
    }
  }
  entries.sort((a, b) => a.key.compareTo(b.key));

  // The md5 of every name followed by its file's bytes, streamed: a save
  // can be large, and nothing needs it whole.
  final digest = _DigestSink();
  final input = md5.startChunkedConversion(digest);
  for (final entry in entries) {
    input.add(utf8.encode(entry.key));
    await for (final chunk in entry.value.openRead()) {
      input.add(chunk);
    }
  }
  input.close();
  return digest.value.toString();
}

/// The (name inside the zip, md5) of every file a bundle push zips from
/// [keys], in its order: files by name (two of one name both count), folders
/// as `<folder>/<path>`; each file read as a stream.
Future<List<(String, String)>> bundleFileDigests(List<io.File> keys) async {
  final files = <(String, String)>[];
  for (final file in keys) {
    if (await io.FileSystemEntity.isDirectory(file.path)) {
      final dirName = p.basename(file.path);
      await for (final child in io.Directory(file.path).list(recursive: true)) {
        if (child is! io.File) continue;
        final relative = p.relative(child.path, from: file.path).replaceAll(r'\', '/');
        files.add(('$dirName/$relative', await md5OfFile(child)));
      }
    } else {
      files.add((p.basename(file.path), await md5OfFile(file)));
    }
  }
  return files;
}

/// Receives the digest of a chunked md5.
class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
