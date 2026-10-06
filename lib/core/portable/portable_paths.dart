import 'dart:io' as io;

import 'package:path/path.dart' as p;

/// Paths stored by a portable copy (see the portable mode spec).
///
/// A path on the same drive as the Freegosy folder is stored as
/// `@freegosy:<relative to the folder>|<absolute>`, so it survives a new drive
/// letter (relative part) and a moved Freegosy folder (absolute part).
/// Windows paths only: portable mode is Windows-only.
class PortablePaths {
  PortablePaths({required this.root, bool Function(String path)? exists})
      : _exists = exists ?? _defaultExists;

  /// The Freegosy folder (where `freegosy.exe` and `portable.txt` are).
  final String root;
  final bool Function(String path) _exists;

  static const String prefix = '@freegosy:';

  /// Set by `PortableMode.install()`; null when this copy isn't portable.
  static PortablePaths? active;

  static final _p = p.windows;
  static final _drivePath = RegExp(r'^[A-Za-z]:\\');

  static bool _defaultExists(String path) =>
      io.FileSystemEntity.typeSync(path) != io.FileSystemEntityType.notFound;

  /// An absolute Windows drive path such as `E:\ROMs`.
  static bool isDrivePath(String value) => _drivePath.hasMatch(value);

  String _drive(String path) => path.substring(0, 1).toUpperCase();

  String toStored(String path) {
    if (!isDrivePath(path) || !isDrivePath(root)) return path;
    if (_drive(path) != _drive(root)) return path;
    final relative = _p.relative(path, from: root);
    return '$prefix$relative|$path';
  }

  String fromStored(String value) {
    if (!value.startsWith(prefix)) return value;
    final body = value.substring(prefix.length);
    final bar = body.indexOf('|'); // '|' can't occur in a Windows path
    final relative = bar < 0 ? body : body.substring(0, bar);
    final absolute = bar < 0 ? '' : body.substring(bar + 1);
    final resolved = _p.normalize(_p.join(root, relative));
    if (_exists(resolved)) return resolved;
    if (absolute.isNotEmpty && _exists(absolute)) return absolute;
    return resolved;
  }

  /// [path] as a portable copy stores it; unchanged when not portable.
  static String store(String path) => active?.toStored(path) ?? path;

  /// A stored value as a usable path. `@freegosy:` values resolve even when
  /// this copy is no longer portable (against the executable's folder).
  static String resolve(String value) {
    if (!value.startsWith(prefix)) return value;
    final paths = active ?? PortablePaths(root: p.dirname(io.Platform.resolvedExecutable));
    return paths.fromStored(value);
  }
}
