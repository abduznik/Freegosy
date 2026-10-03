import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// One save file: its name (no directory) and its bytes.
@immutable
class SaveBlob {
  const SaveBlob(this.name, this.bytes);

  final String name;
  final Uint8List bytes;

  /// The extension, lower-case, with its dot (`.srm`).
  String get extension => p.extension(name).toLowerCase();
}

/// One emulator family's way of storing one system's save. [N] is that
/// system's neutral form, which every format of the system decodes to and
/// encodes from. Pure: bytes and names in, bytes and names out.
abstract class SaveFormat<N> {
  const SaveFormat();

  /// Stable id for logs, e.g. `n64.mupen_srm`.
  String get id;

  /// The RomM `emulator` tags whose saves are in this format. Empty for a
  /// format that is only ever a source, recognised by its files.
  Set<String> get tags;

  /// Whether [files] look like this format (extension, size, header).
  bool recognises(List<SaveBlob> files);

  /// Whether this format applies only to saves tagged with one of [tags],
  /// whatever their files look like (a raw save can't be told by its bytes).
  bool get byTagOnly => false;

  /// The save in neutral form. Throws [FormatException] when [files] aren't
  /// valid for this format.
  N decode(List<SaveBlob> files);

  /// [save] as this format's files, named for [stem], the ROM name the local
  /// emulator looks for. [existing] are the game's save files already on this
  /// machine, for a format that holds more than [save] carries to keep the
  /// rest of it.
  List<SaveBlob> encode(N save, {required String stem, List<SaveBlob> existing = const []});
}

/// The save formats of one system, which share the neutral form [N].
class SaveSystem<N> {
  const SaveSystem({required this.name, required this.slugs, required this.formats});

  final String name;

  /// Freegosy's platform slugs for the system (after canonicalPlatformSlug).
  final Set<String> slugs;
  final List<SaveFormat<N>> formats;

  /// The format of the saves RomM tags [tag], if this system has one.
  SaveFormat<N>? formatForTag(String tag) {
    for (final format in formats) {
      if (format.tags.contains(tag)) return format;
    }
    return null;
  }

  /// [files] converted from the format they're in to the one [targetTag]'s
  /// emulator reads, or why not (see convertSave).
  SaveConversion convert({
    required List<SaveBlob> files,
    String? sourceTag,
    required String targetTag,
    required String stem,
    List<SaveBlob> existing = const [],
  }) {
    final names = files.map((f) => f.name).join(', ');
    SaveFormat<N>? target;
    for (final format in formats) {
      if (format.tags.contains(targetTag)) {
        target = format;
        break;
      }
    }
    if (target == null) {
      _log('no $name save format for "$targetTag" — $names left as it is');
      return const SaveAsIs();
    }

    SaveFormat<N>? source;
    if (sourceTag != null) {
      for (final format in formats) {
        if (format.tags.contains(sourceTag) && (format.byTagOnly || format.recognises(files))) {
          source = format;
          break;
        }
      }
    }
    if (source == null) {
      final candidates = [for (final format in formats) if (format.recognises(files)) format];
      if (candidates.length != 1) {
        return _notConvertible(candidates.isEmpty
            ? 'no $name save format recognises $names'
            : '$names could be ${candidates.map((f) => f.id).join(' or ')}');
      }
      source = candidates.single;
    }
    if (identical(source, target)) return const SaveAsIs();

    try {
      final out = target.encode(source.decode(files), stem: stem, existing: existing);
      if (out.isEmpty) return _notConvertible('$names (${source.id}) holds nothing ${target.id} keeps');
      _log('converted $names from ${source.id} to ${target.id}: ${out.map((f) => f.name).join(', ')}');
      return SaveConverted(out);
    } on FormatException catch (e) {
      return _notConvertible('$names is not valid ${source.id} (${e.message})');
    }
  }

  static SaveNotConvertible _notConvertible(String reason) {
    _log('$reason — left as it is');
    return SaveNotConvertible(reason);
  }

  static void _log(String message) => debugPrint('[SaveSync] [format] $message');
}

/// What convertSave did with a save.
sealed class SaveConversion {
  const SaveConversion();
}

/// The files suit the target as they are: the same format, or no format is
/// known for the target (its strategy takes them as they come).
final class SaveAsIs extends SaveConversion {
  const SaveAsIs();
}

/// The files, in the target's format and under its names.
final class SaveConverted extends SaveConversion {
  const SaveConverted(this.files);
  final List<SaveBlob> files;
}

/// The target has a format, but these files couldn't be put in it.
final class SaveNotConvertible extends SaveConversion {
  const SaveNotConvertible(this.reason);
  final String reason;
}
