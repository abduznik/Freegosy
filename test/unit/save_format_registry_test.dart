import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/formats/save_format_registry.dart';

/// A text "save" stored as `<stem>.<ext>`; the neutral form is the text.
class _TextFormat extends SaveFormat<String> {
  const _TextFormat(this.id, this.ext, this.tags, {this.encodesNothing = false});
  @override
  final String id;
  final String ext;
  @override
  final Set<String> tags;
  final bool encodesNothing;

  @override
  bool recognises(List<SaveBlob> files) => files.length == 1 && files.single.extension == ext;
  @override
  String decode(List<SaveBlob> files) {
    final text = utf8.decode(files.single.bytes);
    if (text == 'corrupt') throw const FormatException('corrupt');
    return text;
  }

  @override
  List<SaveBlob> encode(String save, {required String stem, List<SaveBlob> existing = const []}) =>
      encodesNothing ? [] : [SaveBlob('$stem$ext', Uint8List.fromList(utf8.encode(save)))];
}

const _a = _TextFormat('test.a', '.a', {'emu_a'});
const _b = _TextFormat('test.b', '.b', {'emu_b', 'emu_b2'});
const _alsoA = _TextFormat('test.a2', '.a', {'emu_a2'});
const _empty = _TextFormat('test.e', '.e', {'emu_e'}, encodesNothing: true);

final _systems = <SaveSystem<Object>>[
  const SaveSystem<String>(name: 'N64', slugs: {'n64'}, formats: [_a, _b, _empty]),
  const SaveSystem<String>(name: 'Ambiguous', slugs: {'amb'}, formats: [_a, _alsoA, _b]),
];

SaveBlob _blob(String name, String text) => SaveBlob(name, Uint8List.fromList(utf8.encode(text)));

SaveConversion _convert(String slug, List<SaveBlob> files, {String? from, required String to}) =>
    convertSave(platformSlug: slug, files: files, sourceTag: from, targetTag: to, stem: 'Game (USA)', systems: _systems);

/// The converted files' names; fails the test when it wasn't converted.
List<String> _names(SaveConversion c) {
  expect(c, isA<SaveConverted>());
  return [for (final f in (c as SaveConverted).files) f.name];
}

Matcher _notConvertible(String mentioning) =>
    isA<SaveNotConvertible>().having((c) => c.reason, 'reason', contains(mentioning));

void main() {
  test('converts from the tagged format to the target\'s format, under the ROM stem', () {
    final out = _convert('n64', [_blob('upload.a', 'hello')], from: 'emu_a', to: 'emu_b');
    expect(_names(out), ['Game (USA).b']);
    expect(utf8.decode((out as SaveConverted).files.single.bytes), 'hello');
  });

  test('any of a format\'s tags selects it', () {
    expect(_names(_convert('n64', [_blob('x.a', 'hi')], from: 'emu_a', to: 'emu_b2')), ['Game (USA).b']);
  });

  test('no format for the target tag: as it is (its strategy takes it as it comes)', () {
    expect(_convert('n64', [_blob('x.a', 'hi')], from: 'emu_a', to: 'duckstation'), isA<SaveAsIs>());
  });

  test('an unknown, old ("freegosy") or missing tag falls back to recognising the files', () {
    expect(_names(_convert('n64', [_blob('x.a', 'hi')], from: 'freegosy', to: 'emu_b')), ['Game (USA).b']);
    expect(_names(_convert('n64', [_blob('x.a', 'hi')], to: 'emu_b')), ['Game (USA).b']);
  });

  test('a tagged format that doesn\'t recognise the files falls back to recognising them', () {
    expect(_names(_convert('n64', [_blob('x.a', 'hi')], from: 'emu_b', to: 'emu_b')), ['Game (USA).b']);
  });

  test('files no format recognises: not convertible, saying which', () {
    expect(_convert('n64', [_blob('x.zip', 'hi')], to: 'emu_b'), _notConvertible('x.zip'));
  });

  test('files several formats recognise, with no tag to choose: not convertible', () {
    expect(_convert('amb', [_blob('x.a', 'hi')], to: 'emu_b'), _notConvertible('x.a'));
    expect(_names(_convert('amb', [_blob('x.a', 'hi')], from: 'emu_a2', to: 'emu_b')), ['Game (USA).b']);
  });

  test('already in the target\'s format: as it is, so the save is restored untouched', () {
    expect(_convert('n64', [_blob('x.b', 'hi')], from: 'emu_b', to: 'emu_b2'), isA<SaveAsIs>());
  });

  test('a save that fails to decode: not convertible', () {
    expect(_convert('n64', [_blob('x.a', 'corrupt')], from: 'emu_a', to: 'emu_b'), _notConvertible('x.a'));
  });

  test('an encode that produces no files: not convertible', () {
    expect(_convert('n64', [_blob('x.a', 'hi')], from: 'emu_a', to: 'emu_e'), _notConvertible('x.a'));
  });

  test('RomM\'s platform slugs are matched through their aliases', () {
    // canonicalPlatformSlug: 'ique-player' → 'n64'.
    expect(_convert('ique-player', [_blob('x.a', 'hi')], from: 'emu_a', to: 'emu_b'), isA<SaveConverted>());
    expect(_convert('N64', [_blob('x.a', 'hi')], from: 'emu_a', to: 'emu_b'), isA<SaveConverted>());
  });

  test('a platform with no save system: as it is', () {
    expect(_convert('snes', [_blob('x.a', 'hi')], from: 'emu_a', to: 'emu_b'), isA<SaveAsIs>());
  });

  test('SaveBlob.extension is lower-case', () {
    expect(_blob('GAME.SRM', '').extension, '.srm');
  });

  test('N64 saves are not converted (raw systems and memory cards only)', () {
    expect(saveSystemFor('n64'), isNull);
  });
}
