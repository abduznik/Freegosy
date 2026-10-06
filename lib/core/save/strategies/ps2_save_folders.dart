import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../formats/ps2_memory_card.dart';

/// PS2 saves as they move through RomM: a game's **save folders** (e.g.
/// `BASLUS-20851AC5/…`), the shape PCSX2 folder cards and Argosy use, so
/// every PS2 client can read them. The emulators that keep saves on "file"
/// memory cards (PCSX2's `Mcd00N.ps2` image, RetroArch's LRPS2) take the
/// game's saves off the card to upload them, and put downloaded ones back on
/// the card, leaving the other games' saves as they are.
///
/// LRPS2 keeps its cards in RetroArch's system folder, shared by every game
/// (`pcsx2/memcards/Mcd001.ps2`, `Mcd002.ps2`), or, with its *Shared Memory
/// Cards* option off, one card per game in the save folder (`<content>.ps2`).
class Ps2SaveFolders {
  Ps2SaveFolders._();

  /// The option that picks shared or per-game cards, and its default.
  static const lrps2SharedCardsOption = 'pcsx2_shared_memory_cards';

  /// Whether LRPS2 uses its shared cards, from the contents of the core
  /// option files that apply, most specific first (the game's, its folder's,
  /// the core's, RetroArch's global one). Shared unless one says otherwise.
  static bool lrps2UsesSharedCards(List<String> optionFiles) {
    final line = RegExp('^\\s*$lrps2SharedCardsOption\\s*=\\s*"?(enabled|disabled)"?', multiLine: true);
    for (final contents in optionFiles) {
      final m = line.firstMatch(contents);
      if (m != null) return m.group(1) == 'enabled';
    }
    return true;
  }

  /// Whether the save folder [name] belongs to the game with [serial]
  /// (e.g. `SLUS-20851`). PS2 save folders are named
  /// `<region prefix><serial><suffix>`: `BASLUS-20851AC5`, `BESCES-52438GAMEDATA`.
  static bool isSaveOf(String name, String serial) {
    final s = serial.toUpperCase().replaceAll('_', '-');
    final n = name.toUpperCase().replaceAll('_', '-');
    return n.length >= 2 + s.length && n.substring(2, 2 + s.length) == s;
  }

  /// The PS2 saves in a downloaded save, whatever client made it:
  /// - a zip of save folders (`BASLUS-20851AC5/<file>`), as Freegosy and
  ///   Argosy upload them;
  /// - a zip of a whole PCSX2 folder card (`Mcd001.ps2/<save>/<file>`, or any
  ///   card folder holding a `_pcsx2_superblock`);
  /// - a whole PCSX2 file card (`.ps2`, 8 MB), as older uploads are.
  ///
  /// PCSX2's own bookkeeping files in folder cards (`_pcsx2_index`,
  /// `_pcsx2_superblock`), save states and anything else are left out.
  /// Throws [FormatException] for a `.ps2` card that can't be read.
  static List<Ps2CardSave> savesFromUpload(Uint8List data, String fileName) {
    if (Ps2MemoryCard.looksLikeCard(data)) return Ps2MemoryCard.parse(data).saves;
    if (!fileName.toLowerCase().endsWith('.zip')) return const [];

    final archive = ZipDecoder().decodeBytes(data);
    final cardRoots = <String>{
      for (final e in archive)
        if (e.isFile && p.posix.basename(_path(e.name)) == '_pcsx2_superblock') p.posix.dirname(_path(e.name)),
    };
    final folders = <String, List<Ps2CardFile>>{};
    for (final entry in archive) {
      if (!entry.isFile) continue;
      var parts = p.posix.split(_path(entry.name));
      if (parts.length > 2 && (parts.first.toLowerCase().endsWith('.ps2') || cardRoots.contains(parts.first))) {
        parts = parts.sublist(1);
      }
      if (parts.length != 2) continue; // loose files, states, nested folders
      final (folder, file) = (parts[0], parts[1]);
      if (file.startsWith('_pcsx2_') || !_isSaveFolderName(folder)) continue;
      folders.putIfAbsent(folder, () => []).add(
          Ps2CardFile(name: file, data: Uint8List.fromList(entry.content as List<int>)));
    }
    return [
      for (final MapEntry(key: name, value: files) in folders.entries) Ps2CardSave(name: name, files: files),
    ];
  }

  /// [card] (or a new card when it is missing or was never formatted) with
  /// the saves [belongs] picks replaced by [incoming]. Throws
  /// [FormatException] for a card that can't be read and
  /// [Ps2CardFullException] when the saves don't fit.
  static Uint8List merge(Uint8List? card, List<Ps2CardSave> incoming, bool Function(String name) belongs) {
    final bytes = card == null || Ps2MemoryCard.isUnformatted(card) ? Ps2MemoryCard.formatted() : card;
    return Ps2MemoryCard.parse(bytes).withSaves(incoming, belongs);
  }

  /// A save folder's name: a region prefix and a product code, e.g.
  /// `BASLUS-20851AC5` (the same shape PCSX2 and Argosy look for).
  static bool _isSaveFolderName(String name) =>
      RegExp(r'^B[A-Z]S[A-Z]{3}[-_]\d{5}', caseSensitive: false).hasMatch(name);

  static String _path(String name) => name.replaceAll('\\', '/');
}
