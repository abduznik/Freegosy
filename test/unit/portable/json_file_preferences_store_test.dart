import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/portable/json_file_preferences_store.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences_platform_interface/types.dart';

void main() {
  late io.Directory dir;
  late io.File file;
  final problems = <String>[];

  setUp(() async {
    dir = await io.Directory.systemTemp.createTemp('json_prefs');
    file = io.File(p.join(dir.path, 'shared_preferences.json'));
    problems.clear();
  });
  tearDown(() => dir.delete(recursive: true));

  JsonFilePreferencesStore store({String Function(String)? toStored, String Function(String)? fromStored}) =>
      JsonFilePreferencesStore(file,
          toStored: toStored,
          fromStored: fromStored,
          onProblem: problems.add,
          now: () => DateTime(2026, 10, 5, 12, 0, 0));

  test('every value type round-trips through the file', () async {
    final a = store();
    await a.setValue('String', 'flutter.s', 'text');
    await a.setValue('Bool', 'flutter.b', true);
    await a.setValue('Int', 'flutter.i', 42);
    await a.setValue('Double', 'flutter.d', 1.5);
    await a.setValue('StringList', 'flutter.l', <String>['x', 'y']);
    await a.flush();

    final all = await store().getAll();
    expect(all, {
      'flutter.s': 'text',
      'flutter.b': true,
      'flutter.i': 42,
      'flutter.d': 1.5,
      'flutter.l': ['x', 'y'],
    });
    expect(all['flutter.l'], isA<List<String>>());
  });

  test('reads a file written by shared_preferences_windows as is', () async {
    await file.writeAsString('{"flutter.rommBaseUrl":"https://romm.example","flutter.launch_fullscreen":false,'
        '"flutter.columns":5,"flutter.recent":["a","b"]}');
    expect(await store().getAll(), {
      'flutter.rommBaseUrl': 'https://romm.example',
      'flutter.launch_fullscreen': false,
      'flutter.columns': 5,
      'flutter.recent': ['a', 'b'],
    });
  });

  test('getAll only returns flutter. keys; the parameter filters work', () async {
    await file.writeAsString('{"flutter.a":1,"flutter.b":2,"other.c":3}');
    final s = store();
    expect((await s.getAll()).keys, ['flutter.a', 'flutter.b']);
    expect(
        (await s.getAllWithParameters(
                GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.', allowList: {'flutter.b'}))))
            .keys,
        ['flutter.b']);
    await s.clearWithParameters(ClearParameters(filter: PreferencesFilter(prefix: 'flutter.', allowList: {'flutter.a'})));
    await s.flush();
    expect(jsonDecode(await file.readAsString()), {'flutter.b': 2, 'other.c': 3});
  });

  test('remove and clear', () async {
    final s = store();
    await s.setValue('Int', 'flutter.a', 1);
    await s.setValue('Int', 'flutter.b', 2);
    await s.remove('flutter.a');
    expect((await s.getAll()).keys, ['flutter.b']);
    await s.clear();
    await s.flush();
    expect(jsonDecode(await file.readAsString()), isEmpty);
  });

  test('writes go through a .tmp file that is renamed into place', () async {
    final s = store();
    await s.setValue('String', 'flutter.a', 'x');
    await s.flush();
    expect(await io.File('${file.path}.tmp').exists(), isFalse);
    expect(jsonDecode(await file.readAsString()), {'flutter.a': 'x'});
  });

  test('concurrent writes all land, in order', () async {
    final s = store();
    await Future.wait([for (var i = 0; i < 20; i++) s.setValue('Int', 'flutter.n', i)]);
    await s.flush();
    expect(jsonDecode(await file.readAsString()), {'flutter.n': 19});
  });

  test('a leftover .tmp is used when the main file is missing', () async {
    await io.File('${file.path}.tmp').writeAsString('{"flutter.a":"from tmp"}');
    expect(await store().getAll(), {'flutter.a': 'from tmp'});
  });

  test('a leftover .tmp is ignored when the main file is good', () async {
    await file.writeAsString('{"flutter.a":"main"}');
    await io.File('${file.path}.tmp').writeAsString('{"flutter.a":"tmp"}');
    expect(await store().getAll(), {'flutter.a': 'main'});
  });

  test('a damaged file is kept aside and the store starts empty', () async {
    await file.writeAsString('{not json');
    expect(await store().getAll(), isEmpty);
    expect(await io.File(p.join(dir.path, 'shared_preferences.corrupt-20261005-120000.json')).exists(), isTrue);
    expect(problems.single, contains('shared_preferences.corrupt-20261005-120000.json'));
  });

  test('path values are converted on write and resolved on read, in strings and lists', () async {
    String to(String v) => v.startsWith('E:') ? '@freegosy:${v.substring(3)}' : v;
    String from(String v) => v.startsWith('@freegosy:') ? 'F:\\${v.substring(10)}' : v;
    final s = store(toStored: to, fromStored: from);
    await s.setValue('String', 'flutter.romsRootPath', r'E:\ROMs');
    await s.setValue('StringList', 'flutter.dirs', <String>[r'E:\A', r'D:\B']);
    await s.setValue('String', 'flutter.url', 'https://x');
    await s.flush();

    expect(jsonDecode(await file.readAsString()), {
      'flutter.romsRootPath': '@freegosy:ROMs',
      'flutter.dirs': ['@freegosy:A', r'D:\B'],
      'flutter.url': 'https://x',
    });
    final again = await store(toStored: to, fromStored: from).getAll();
    expect(again['flutter.romsRootPath'], r'F:\ROMs');
    expect(again['flutter.dirs'], [r'F:\A', r'D:\B']);
  });

  test('replaceAll swaps every value and persists them', () async {
    final s = store();
    await s.setValue('String', 'flutter.old', 'x');
    await s.replaceAll({'flutter.new': 'y'});
    await s.setValue('Int', 'flutter.later', 1);
    await s.flush();
    expect(jsonDecode(await file.readAsString()), {'flutter.new': 'y', 'flutter.later': 1});
  });

  test('a failed write is reported and returns false', () async {
    // A file where the settings folder should be: the drive "went away".
    await io.File(p.join(dir.path, 'blocked')).writeAsString('');
    final s = JsonFilePreferencesStore(io.File(p.join(dir.path, 'blocked', 'prefs.json')), onProblem: problems.add);
    expect(await s.setValue('Int', 'flutter.a', 1), isFalse);
    expect(problems.single, contains("Can't save settings"));
  });

  test('a problem handler that throws never wedges the write queue', () async {
    await io.File(p.join(dir.path, 'blocked')).writeAsString('');
    final s = JsonFilePreferencesStore(io.File(p.join(dir.path, 'blocked', 'prefs.json')),
        onProblem: (_) => throw StateError('no messenger'));
    const limit = Duration(seconds: 5);
    expect(await s.setValue('Int', 'flutter.a', 1).timeout(limit), isFalse);
    expect(await s.setValue('Int', 'flutter.b', 2).timeout(limit), isFalse);
    await s.flush().timeout(limit);
  });

  test('a problem handler that throws while loading a damaged file is contained', () async {
    await file.writeAsString('[]');
    final s = JsonFilePreferencesStore(file, onProblem: (_) => throw StateError('no messenger'));
    expect(await s.getAll(), isEmpty);
  });

  test('a corrupt JSON file with wrong shape (array) is kept aside and the store starts empty', () async {
    await file.writeAsString('[]');
    expect(await store().getAll(), isEmpty);
    expect(await io.File(p.join(dir.path, 'shared_preferences.corrupt-20261005-120000.json')).exists(), isTrue);
    expect(problems.single, contains('shared_preferences.corrupt-20261005-120000.json'));
  });

  test('encoding errors reading files at startup are handled gracefully', () async {
    // Write invalid UTF-8 bytes that cause readAsStringSync to throw FileSystemException.
    await file.writeAsBytes([0xC3, 0x28, 0xFF]);
    problems.clear();
    final s = store();
    expect(await s.getAll(), isEmpty);
    expect(problems.single, contains('Settings file could not be read'));
    // Verify the store is still usable after the read error.
    expect(await s.setValue('Int', 'flutter.a', 1), isTrue);
    await s.flush();
    expect(await store().getAll(), {'flutter.a': 1});
  });

  test('a corrupt .tmp file is quarantined and reported', () async {
    await io.File('${file.path}.tmp').writeAsString('[]');
    problems.clear();
    expect(await store().getAll(), isEmpty);
    expect(await io.File(p.join(dir.path, 'shared_preferences.corrupt-20261005-120000.json')).exists(), isTrue);
    expect(problems.single, contains('Temporary settings file was damaged'));
  });
}
