import 'dart:typed_data';

import 'save_format.dart';

/// A save every emulator of a raw system keeps as the same bytes; only the
/// name differs (`.sav`, `.srm`), and each save strategy names it the way
/// its emulator reads it. Never converted.
class RawSaveFormat extends SaveFormat<Uint8List> {
  const RawSaveFormat(this.id, this.tags);

  @override
  final String id;
  @override
  final Set<String> tags;

  /// Never by the files alone: any emulator's save would pass, including
  /// ones not verified to keep the same bytes. Only by tag (see [byTagOnly]).
  @override
  bool recognises(List<SaveBlob> files) => false;
  @override
  bool get byTagOnly => true;
  @override
  Uint8List decode(List<SaveBlob> files) => files.single.bytes;
  @override
  List<SaveBlob> encode(Uint8List save, {required String stem, List<SaveBlob> existing = const []}) =>
      throw UnsupportedError('a raw save is never converted');
}

/// A system whose saves the emulators tagged [tags] share as they are.
SaveSystem<Uint8List> rawSaveSystem({required String name, required Set<String> slugs, required Set<String> tags}) =>
    SaveSystem<Uint8List>(name: name, slugs: slugs, formats: [RawSaveFormat('${name.toLowerCase()}.raw', tags)]);

/// One line per system. Add a line only for emulators verified to keep the
/// same bytes (a real save from each, loaded in the other).
final List<SaveSystem<Object>> kRawSaveSystems = [
  // melonDS standalone `.sav`, RetroArch's melonDS and melonDS DS cores `.srm`.
  rawSaveSystem(name: 'NDS', slugs: {'nds', 'nintendo-ds', 'ds'}, tags: {'melonds', 'melondsds'}),
];
