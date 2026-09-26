import 'dart:io' as io;
import 'dart:isolate';
import 'package:flutter/foundation.dart';

/// Reads the file version from a Windows executable's `VS_FIXEDFILEINFO`
/// resource (what Explorer shows as "File version"), without any native
/// code: the block is found by its signature `0xFEEF04BD`.
class PeVersionReader {
  PeVersionReader._();

  static final Map<String, ({DateTime modified, String? version})> _cache = {};

  /// `major.minor.build.revision` from [bytes], or null if [bytes] is not a
  /// PE file (`MZ`) or carries no version block.
  static String? parse(Uint8List bytes) {
    if (bytes.length < 2 || bytes[0] != 0x4D || bytes[1] != 0x5A) return null;
    final data = ByteData.sublistView(bytes);
    for (var i = 2; i + 16 <= bytes.length; i++) {
      if (bytes[i] != 0xBD || bytes[i + 1] != 0x04 || bytes[i + 2] != 0xEF || bytes[i + 3] != 0xFE) {
        continue;
      }
      // dwStrucVersion must also match VS_FFI_STRUCVERSION (1.0); otherwise
      // this is a false hit on the signature bytes elsewhere in the file.
      if (data.getUint32(i + 4, Endian.little) != 0x00010000) continue;
      final ms = data.getUint32(i + 8, Endian.little);
      final ls = data.getUint32(i + 12, Endian.little);
      return '${ms >> 16}.${ms & 0xFFFF}.${ls >> 16}.${ls & 0xFFFF}';
    }
    return null;
  }

  /// [parse] on the file at [path], off the UI isolate, cached per path and
  /// modified time. Null on any failure.
  static Future<String?> fileVersion(String path) async {
    try {
      final modified = await io.File(path).lastModified();
      final cached = _cache[path];
      if (cached != null && cached.modified == modified) return cached.version;
      final version = await Isolate.run(() => parse(io.File(path).readAsBytesSync()));
      _cache[path] = (modified: modified, version: version);
      return version;
    } catch (e) {
      debugPrint('[Emulator] cannot read the version of $path: $e');
      return null;
    }
  }
}
