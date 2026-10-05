import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/formats/ps1_card_formats.dart';
import 'package:freegosy/core/save/formats/save_format_registry.dart';

import '../helpers/ps1_card_builder.dart';

/// PS1 cards: a raw 128 KB card is the same bytes as DuckStation's `.mcd`
/// and RetroArch's `<content>.srm`; only the name differs. See
/// docs/save-interop.md.
void main() {
  const stem = 'Colin McRae Rally 2.0 (Europe) (En,Fr,De,Es,It)';
  final card = buildPs1Card([(name: 'BESLES-02605-SETTING', blocks: [1], fill: 0x11)]);

  List<SaveBlob>? toRetroArch(String name, Uint8List bytes, {String slug = 'psx', String? from, String to = 'mednafen_psx_hw'}) =>
      switch (convertSave(platformSlug: slug, files: [SaveBlob(name, bytes)], sourceTag: from, targetTag: to, stem: stem)) {
        SaveConverted(:final files) => files,
        _ => null,
      };

  test('a DuckStation port-1 card becomes the game\'s .srm, same bytes', () {
    final out = toRetroArch('${stem}_1.mcd', card, from: 'duckstation')!;
    expect(out.single.name, '$stem.srm');
    expect(out.single.bytes, card);
  });

  test('every RetroArch PS1 core reads the .srm', () {
    for (final core in ['pcsx_rearmed', 'mednafen_psx_hw', 'mednafen_psx', 'swanstation']) {
      expect(toRetroArch('x_1.mcd', card, to: core)!.single.name, '$stem.srm', reason: core);
    }
  });

  test('other clients\' port-1 names convert too', () {
    for (final name in ['SLES-02605_1.mcd', 'Colin McRae Rally 2.0_1.mcd', 'pcsx-card1.mcd', 'shared_card_1.mcd', 'mcd1.mcd', 'card.mcd', 'X_1.MCD']) {
      expect(Ps1McdFormat.isPort1CardName(name), isTrue, reason: name);
      expect(toRetroArch(name, card)?.single.name, '$stem.srm', reason: name);
    }
  });

  test('a card for another port keeps its name', () {
    for (final name in ['${stem}_2.mcd', 'SLES-02605_2.mcd', 'pcsx-card2.mcd', 'shared_card_2.mcd', 'mcd2.mcd']) {
      expect(Ps1McdFormat.isPort1CardName(name), isFalse, reason: name);
      expect(toRetroArch(name, card), isNull, reason: name);
    }
  });

  test('a .mcd that is not a raw PS1 card keeps its name', () {
    expect(toRetroArch('${stem}_1.mcd', Uint8List(1000)), isNull);
    expect(toRetroArch('x_1.mcd', Uint8List(128 * 1024)), isNull, reason: 'the right size but no MC header');
  });

  test('a .srm card going to RetroArch is already right', () {
    expect(toRetroArch('$stem.srm', card, from: 'pcsx_rearmed'), isNull);
    expect(toRetroArch('$stem.SRM', card, from: 'duckstation'), isNull);
  });

  test('a RetroArch .srm card going to DuckStation becomes its port-1 card, same bytes; its own card stays as it is', () {
    final out = toRetroArch('$stem.srm', card, from: 'pcsx_rearmed', to: 'duckstation')!;
    expect(out.single.name, '${stem}_1.mcd');
    expect(out.single.bytes, card);
    expect(toRetroArch('${stem}_1.mcd', card, to: 'duckstation'), isNull);
  });

  test('only PS1 games', () {
    expect(toRetroArch('x_1.mcd', card, slug: 'ps1'), isNotNull);
    expect(toRetroArch('x_1.mcd', card, slug: 'playstation'), isNotNull);
    expect(toRetroArch('x_1.mcd', card, slug: 'saturn'), isNull);
  });

  test('the .mcd format encodes a port-1 card name', () {
    expect(const Ps1McdFormat().encode(card, stem: stem).single.name, '${stem}_1.mcd');
  });
}
