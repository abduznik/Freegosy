import 'dart:typed_data';

import 'package:zstandard/zstandard.dart';

/// Decompresses one complete zstd frame; null when it can't.
typedef ZstdDecompressor = Future<Uint8List?> Function(Uint8List compressed);

/// The zstandard plugin. Tests pass a fake [ZstdDecompressor] instead: the
/// plugin needs the Flutter engine.
Future<Uint8List?> zstandardDecompress(Uint8List compressed) => Zstandard().decompress(compressed);
