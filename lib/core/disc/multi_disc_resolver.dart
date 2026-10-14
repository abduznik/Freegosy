import 'dart:io' as io;

import 'package:path/path.dart' as p;

/// Finds the other discs of a multi-disc game next to a resolved ROM file.
///
/// The ROM lookup collapses a game folder to one file (the `.m3u` playlist, or
/// else a disc image), so the disc picker never saw the other discs (#54).
class MultiDiscResolver {
  static final RegExp _discToken = RegExp(
    r'(?:disc|disk|cd)\s*[_\s]?\s*(\d+)',
    caseSensitive: false,
  );

  /// The disc number in [fileName] ("Game (Disc 2).rvz" → 2), or null.
  static int? discNumber(String fileName) {
    final m = _discToken.firstMatch(p.basenameWithoutExtension(fileName));
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// The disc to boot when no playlist says otherwise: lowest disc number,
  /// then name. Files without a disc number sort last.
  static String pickFirstDisc(Iterable<String> paths) {
    final sorted = paths.toList()
      ..sort((a, b) {
        final na = discNumber(a) ?? 1 << 30;
        final nb = discNumber(b) ?? 1 << 30;
        return na != nb ? na.compareTo(nb) : a.toLowerCase().compareTo(b.toLowerCase());
      });
    return sorted.first;
  }

  /// Discs of the game [romPath] belongs to, in the shape the disc picker
  /// takes (`file_name`, `file_size_bytes`), or an empty list when it is a
  /// single-disc game. For an `.m3u` the playlist comes first, then the discs
  /// it lists; otherwise sibling files that differ only in the disc number.
  static Future<List<Map<String, dynamic>>> discsFor(String romPath) async {
    final file = io.File(romPath);
    if (!await file.exists()) return const [];
    final dir = p.dirname(romPath);

    final discs = <String>[];
    final isPlaylist = p.extension(romPath).toLowerCase() == '.m3u';
    if (isPlaylist) {
      for (final raw in await file.readAsLines()) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final full = p.normalize(p.isAbsolute(line) ? line : p.join(dir, line));
        if (await io.File(full).exists() && !discs.contains(full)) discs.add(full);
      }
    } else {
      final number = discNumber(romPath);
      if (number == null) return const [];
      final template = _template(p.basename(romPath));
      await for (final e in io.Directory(dir).list()) {
        if (e is io.File &&
            p.extension(e.path).toLowerCase() == p.extension(romPath).toLowerCase() &&
            _template(p.basename(e.path)) == template) {
          discs.add(e.path);
        }
      }
      discs.sort((a, b) => (discNumber(a) ?? 0).compareTo(discNumber(b) ?? 0));
    }
    if (discs.length < 2) return const [];

    final ordered = [if (isPlaylist) romPath, ...discs];
    return [
      for (final path in ordered)
        {
          'file_name': p.relative(path, from: dir),
          'file_size_bytes': (await io.File(path).stat()).size,
        },
    ];
  }

  static String _template(String name) =>
      name.toLowerCase().replaceFirst(_discToken, 'disc#');
}
