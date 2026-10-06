import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'ps1_memory_card.dart';
import 'save_format.dart';

/// A raw 128 KB PS1 memory card as a `.mcd` file for port 1: DuckStation's
/// `<name>_1.mcd`, its shared `shared_card_1.mcd` or legacy `mcd1.mcd`,
/// PCSX-ReARMed's `<serial>_1.mcd` / `pcsx-card1.mcd`, or a `.mcd` with no
/// port in its name.
///
/// DuckStation's cards. DuckStation reads RetroArch's `.srm` cards as well; a
/// card converted for it is written as `<stem>_1.mcd`, port 1, and its own
/// strategy picks the card file and port it goes to.
class Ps1McdFormat extends SaveFormat<Uint8List> {
  const Ps1McdFormat();

  static final _port = RegExp(r'(?:_|^mcd|card)(\d+)\.mcd$');

  /// Whether [fileName] names a card for port 1 (see the class comment).
  static bool isPort1CardName(String fileName) {
    final base = p.basename(fileName).toLowerCase();
    if (!base.endsWith('.mcd')) return false;
    final port = _port.firstMatch(base)?.group(1);
    return port == null || int.parse(port) == 1;
  }

  @override
  String get id => 'ps1.mcd';
  @override
  Set<String> get tags => const {'duckstation'};

  @override
  bool recognises(List<SaveBlob> files) =>
      files.length == 1 && isPort1CardName(files.single.name) && Ps1MemoryCard.looksLikeCard(files.single.bytes);

  @override
  Uint8List decode(List<SaveBlob> files) {
    if (!recognises(files)) throw const FormatException('not a port-1 PS1 memory card');
    return files.single.bytes;
  }

  @override
  List<SaveBlob> encode(Uint8List save, {required String stem, List<SaveBlob> existing = const []}) => [SaveBlob('${stem}_1.mcd', save)];
}

/// A PS1 memory card as RetroArch's PS1 cores keep card 1 by default: the
/// game's `<content>.srm`, the same raw 128 KB card.
class Ps1SrmFormat extends SaveFormat<Uint8List> {
  const Ps1SrmFormat();

  @override
  String get id => 'ps1.retroarch_srm';
  @override
  Set<String> get tags => const {'pcsx_rearmed', 'mednafen_psx_hw', 'mednafen_psx', 'swanstation'};

  @override
  bool recognises(List<SaveBlob> files) =>
      files.length == 1 && files.single.extension == '.srm' && Ps1MemoryCard.looksLikeCard(files.single.bytes);

  @override
  Uint8List decode(List<SaveBlob> files) {
    if (!recognises(files)) throw const FormatException('not a PS1 memory card .srm');
    return files.single.bytes;
  }

  @override
  List<SaveBlob> encode(Uint8List save, {required String stem, List<SaveBlob> existing = const []}) => [SaveBlob('$stem.srm', save)];
}

const ps1SaveSystem = SaveSystem<Uint8List>(
  name: 'PS1',
  slugs: {'psx', 'ps1', 'playstation'},
  formats: [Ps1SrmFormat(), Ps1McdFormat()],
);
