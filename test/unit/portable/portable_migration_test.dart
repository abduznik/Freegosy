import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/portable/portable_migration.dart';
import 'package:freegosy/core/portable/portable_paths.dart';
import 'package:freegosy/core/storage/secret_store.dart';
import 'package:path/path.dart' as p;

class _MapStore implements SecretStore {
  _MapStore([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw const io.FileSystemException('disk full');
    values[key] = value;
  }
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
}

void main() {
  late io.Directory tmp;
  late String root, support, documents;

  setUp(() async {
    tmp = await io.Directory.systemTemp.createTemp('migration');
    root = p.join(tmp.path, 'Freegosy');
    support = p.join(tmp.path, 'AppData', 'freegosy');
    documents = p.join(tmp.path, 'Documents');
    await io.Directory(root).create(recursive: true);
    await io.Directory(documents).create(recursive: true);
    await io.File(p.join(support, 'shared_preferences.json'))
        .create(recursive: true)
        .then((f) => f.writeAsString(jsonEncode({'flutter.rommBaseUrl': 'https://romm', 'flutter.columns': 5})));
    await io.File(p.join(support, 'flutter_secure_storage.dat')).writeAsString('secret-file');
    await io.File(p.join(support, 'backups', '1', 'a.zip')).create(recursive: true);
    await io.File(p.join(support, 'ROMs', 'snes', 'game.sfc')).create(recursive: true);
    await io.File(p.join(support, 'Emulators', 'x.exe')).create(recursive: true);
    await io.File(p.join(documents, 'freegosy_backups.hive')).writeAsString('hive');
    await io.File(p.join(documents, 'other_app.hive')).writeAsString('other');
    await io.File(p.join(documents, 'freegosy_backups.lock')).writeAsString('lock');
    await io.File(p.join(documents, 'unrelated.docx')).writeAsString('doc');
  });
  tearDown(() => tmp.delete(recursive: true));

  PortableMigration migration() => PortableMigration(
      root: root,
      installedSupportDir: support,
      installedDocumentsDir: documents,
      now: () => DateTime(2026, 10, 5, 12));

  Map<String, dynamic> json(String path) => jsonDecode(io.File(path).readAsStringSync()) as Map<String, dynamic>;
  // On Windows the temp folder is on the same drive as root, so paths in the
  // portable settings file are stored as @freegosy: values.
  String resolved(Object? value) => PortablePaths(root: root, exists: (_) => false).fromStored(value as String);

  group('toPortable', () {
    test('copies settings, support, Hive files and secrets, then writes the marker', () async {
      final installed = _MapStore({'rommPassword': 'pw'});
      final portable = _MapStore();
      final m = migration();
      await m.toPortable(includeDefaultFolders: false, installedSecrets: installed, portableSecrets: portable);

      final prefs = json(p.join(root, 'userdata', 'shared_preferences.json'));
      expect(prefs['flutter.rommBaseUrl'], 'https://romm');
      expect(prefs['flutter.columns'], 5);
      expect(prefs['flutter.romsRootPath'], endsWith(p.join('AppData', 'freegosy', 'ROMs')));
      expect(prefs['flutter.emulatorsRootPath'], endsWith(p.join('AppData', 'freegosy', 'Emulators')));
      expect(resolved(prefs['flutter.portable_rebase_backups_from']), p.normalize(support));
      expect(resolved(prefs['flutter.portable_rebase_backups_to']), p.normalize(p.join(root, 'userdata', 'support')));
      expect(io.File(p.join(root, 'userdata', 'support', 'backups', '1', 'a.zip')).existsSync(), isTrue);
      expect(io.Directory(p.join(root, 'userdata', 'support', 'ROMs')).existsSync(), isFalse);
      expect(io.File(p.join(root, 'userdata', 'support', 'shared_preferences.json')).existsSync(), isFalse);
      expect(io.File(p.join(root, 'userdata', 'support', 'flutter_secure_storage.dat')).existsSync(), isFalse);
      expect(io.File(p.join(root, 'userdata', 'documents', 'freegosy_backups.hive')).existsSync(), isTrue);
      expect(io.File(p.join(root, 'userdata', 'documents', 'freegosy_backups.lock')).existsSync(), isFalse);
      expect(io.File(p.join(root, 'userdata', 'documents', 'unrelated.docx')).existsSync(), isFalse);
      expect(io.File(p.join(root, 'userdata', 'documents', 'other_app.hive')).existsSync(), isFalse, reason: 'not a Freegosy box');
      expect(portable.values, {'rommPassword': 'pw'});
      expect(io.File(m.markerPath).existsSync(), isTrue);
      expect(io.File(p.join(support, 'ROMs', 'snes', 'game.sfc')).existsSync(), isTrue, reason: 'copy, never move');
    });

    test('ROMs and emulators are copied when asked, and no root path is written', () async {
      await migration().toPortable(includeDefaultFolders: true, installedSecrets: _MapStore(), portableSecrets: _MapStore());
      expect(io.File(p.join(root, 'userdata', 'support', 'ROMs', 'snes', 'game.sfc')).existsSync(), isTrue);
      expect(json(p.join(root, 'userdata', 'shared_preferences.json')).containsKey('flutter.romsRootPath'), isFalse);
    });

    test('a failure before the marker removes data and writes no marker', () async {
      final m = migration();
      await expectLater(
          m.toPortable(
              includeDefaultFolders: false,
              installedSecrets: _MapStore({'a': 'b'}),
              portableSecrets: _MapStore()..failWrites = true),
          throwsA(isA<io.FileSystemException>()));
      expect(io.Directory(m.dataDir).existsSync(), isFalse);
      expect(io.File(m.markerPath).existsSync(), isFalse);
    });
  });

  test('the RetroAchievements token file is never copied, in any direction', () async {
    const cfg = 'retroarch_achievements.cfg';
    await io.File(p.join(support, cfg)).writeAsString('cheevos_token = "pc"');
    await io.File(p.join(support, 'backups', cfg)).writeAsString('nested');
    await migration().toPortable(includeDefaultFolders: false, installedSecrets: _MapStore(), portableSecrets: _MapStore());
    expect(io.File(p.join(root, 'userdata', 'support', cfg)).existsSync(), isFalse);
    expect(io.File(p.join(root, 'userdata', 'support', 'backups', cfg)).existsSync(), isFalse);

    await migration().importInstalled(includeDefaultFolders: false);
    expect(io.File(p.join(root, 'userdata', 'support', cfg)).existsSync(), isFalse);

    await io.File(p.join(root, 'userdata', 'support', cfg)).writeAsString('cheevos_token = "stick"');
    await migration().toInstalled(includeDefaultFolders: false);
    expect(io.File(p.join(support, cfg)).existsSync(), isFalse);
  });

  group('makePortableFresh', () {
    test('writes a settings file that skips the import offer, then the marker', () async {
      final m = migration();
      await m.makePortableFresh();
      expect(json(p.join(root, 'userdata', 'shared_preferences.json')), {'flutter.portable_skip_import_offer': true});
      expect(io.File(m.markerPath).existsSync(), isTrue);
      expect(m.portableDataModified, isNotNull);
    });

    test('keeps settings left from an earlier portable period', () async {
      final m = migration();
      expect(m.portableDataModified, isNull);
      await io.File(p.join(root, 'userdata', 'shared_preferences.json'))
          .create(recursive: true)
          .then((f) => f.writeAsString(jsonEncode({'flutter.rommBaseUrl': 'old'})));
      await m.makePortableFresh();
      expect(json(p.join(root, 'userdata', 'shared_preferences.json')), {'flutter.rommBaseUrl': 'old'});
      expect(io.File(m.markerPath).existsSync(), isTrue);
    });
  });

  group('importInstalled', () {
    test('copies files, hands secrets over after restart, returns the settings', () async {
      final values = await migration().importInstalled(includeDefaultFolders: false);
      expect(values['flutter.rommBaseUrl'], 'https://romm');
      expect(values['flutter.portable_pending_import_secrets'], isTrue);
      expect(io.File(p.join(root, 'userdata', 'support', 'flutter_secure_storage.dat')).readAsStringSync(), 'secret-file');
      expect(io.File(p.join(root, 'portable.txt')).existsSync(), isFalse, reason: 'the marker is already there or not ours to write');
      // The running copy has its own Hive files open; PortableMode.install
      // swaps the .import files in at the next start.
      expect(io.File(p.join(root, 'userdata', 'documents', 'freegosy_backups.hive.import')).existsSync(), isTrue);
      expect(io.File(p.join(root, 'userdata', 'documents', 'freegosy_backups.hive')).existsSync(), isFalse);
    });

    test('a failure removes the .import files and the copied secure file', () async {
      // A directory where the secure file is copied to makes that step fail
      // after the Hive files were already copied.
      await io.Directory(p.join(root, 'userdata', 'support', 'flutter_secure_storage.dat')).create(recursive: true);
      await expectLater(migration().importInstalled(includeDefaultFolders: false), throwsA(isA<io.FileSystemException>()));
      expect(io.File(p.join(root, 'userdata', 'documents', 'freegosy_backups.hive.import')).existsSync(), isFalse);
      expect(io.Directory(p.join(root, 'userdata', 'documents')).listSync().where((e) => e.path.endsWith('.import')), isEmpty);
    });
  });

  group('toInstalled', () {
    setUp(() async {
      await io.File(p.join(root, 'portable.txt')).writeAsString('');
      await io.File(p.join(root, 'userdata', 'shared_preferences.json')).create(recursive: true).then((f) => f.writeAsString(
          jsonEncode({'flutter.rommBaseUrl': 'https://portable', 'flutter.romsRootPath': '@freegosy:..\\ROMs|E:\\ROMs'})));
      await io.File(p.join(root, 'userdata', 'support', 'backups', '2', 'b.zip')).create(recursive: true);
      await io.File(p.join(root, 'userdata', 'support', 'ROMs', 'gba', 'g.gba')).create(recursive: true);
      await io.File(p.join(root, 'userdata', 'documents', 'freegosy_backups.hive')).create(recursive: true);
    });

    test('backs up the PC data, copies everything back as absolute paths, deletes the marker', () async {
      final m = migration();
      await m.toInstalled(includeDefaultFolders: false);

      expect(io.Directory('$support.before-portable-20261005-120000').existsSync(), isTrue);
      expect(io.File(p.join(documents, 'freegosy_backups.hive.before-portable-20261005-120000')).existsSync(), isTrue);
      final prefs = json(p.join(support, 'shared_preferences.json'));
      expect(prefs['flutter.rommBaseUrl'], 'https://portable');
      expect((prefs['flutter.romsRootPath'] as String).startsWith('@freegosy:'), isFalse);
      expect(prefs['flutter.portable_pending_credentials'], m.dataDir);
      expect(prefs['flutter.portable_rebase_backups_from'], p.join(root, 'userdata', 'support'));
      expect(prefs['flutter.portable_rebase_backups_to'], support);
      expect(io.File(p.join(support, 'backups', '2', 'b.zip')).existsSync(), isTrue);
      // The PC's own ROMs and emulators stay in place; the stick's aren't copied.
      expect(io.File(p.join(support, 'ROMs', 'snes', 'game.sfc')).existsSync(), isTrue);
      expect(io.File(p.join(support, 'Emulators', 'x.exe')).existsSync(), isTrue);
      expect(io.File(p.join(support, 'ROMs', 'gba', 'g.gba')).existsSync(), isFalse);
      expect(io.Directory(p.join('$support.before-portable-20261005-120000', 'ROMs')).existsSync(), isFalse);
      expect(io.File(p.join(documents, 'freegosy_backups.hive')).existsSync(), isTrue);
      expect(io.File(p.join(documents, 'other_app.hive')).readAsStringSync(), 'other', reason: 'not a Freegosy box');
      expect(io.File(p.join(documents, 'other_app.hive.before-portable-20261005-120000')).existsSync(), isFalse);
      expect(io.File(m.markerPath).existsSync(), isFalse);
      expect(io.Directory(m.dataDir).existsSync(), isTrue, reason: 'data stays on the stick');
    });

    test('a late failure puts the renamed PC support folder back where it was', () async {
      // The marker can not be deleted (it is a directory), the very last step: the
      // PC's support folder and Hive file were renamed aside and everything was copied.
      await io.File(p.join(root, 'portable.txt')).delete();
      await io.Directory(p.join(root, 'portable.txt')).create();
      final m = migration();

      await expectLater(m.toInstalled(includeDefaultFolders: false), throwsA(isA<io.FileSystemException>()));

      expect(io.Directory(m.markerPath).existsSync(), isTrue, reason: 'marker untouched');
      expect(json(p.join(support, 'shared_preferences.json'))['flutter.rommBaseUrl'], 'https://romm');
      expect(io.File(p.join(support, 'flutter_secure_storage.dat')).readAsStringSync(), 'secret-file');
      expect(io.File(p.join(support, 'backups', '1', 'a.zip')).existsSync(), isTrue);
      expect(io.File(p.join(support, 'backups', '2', 'b.zip')).existsSync(), isFalse, reason: 'portable data removed');
      expect(io.File(p.join(documents, 'freegosy_backups.hive')).readAsStringSync(), 'hive');
      expect(io.File(p.join(documents, 'other_app.hive')).readAsStringSync(), 'other');
      expect(io.File(p.join(support, 'ROMs', 'snes', 'game.sfc')).existsSync(), isTrue, reason: 'moved back, then renamed back');
      expect(io.File(p.join(support, 'Emulators', 'x.exe')).existsSync(), isTrue);
      expect(io.Directory(tmp.path).listSync(recursive: true).where((e) => e.path.contains('before-portable')), isEmpty);
    });

    test('copying ROMs and emulators keeps a folder the PC already has and copies the others', () async {
      await io.Directory(p.join(support, 'Emulators')).delete(recursive: true);
      await io.File(p.join(root, 'userdata', 'support', 'Emulators', 'e.exe')).create(recursive: true);
      final m = migration();
      expect(m.installedDefaultFolders, ['ROMs']);

      await m.toInstalled(includeDefaultFolders: true);

      expect(io.File(p.join(support, 'ROMs', 'snes', 'game.sfc')).existsSync(), isTrue);
      expect(io.File(p.join(support, 'ROMs', 'gba', 'g.gba')).existsSync(), isFalse, reason: "the PC's ROMs win");
      expect(io.File(p.join(support, 'Emulators', 'e.exe')).existsSync(), isTrue);
    });

    test("settings point at the stick's folder only when the PC has none of its own", () async {
      await io.File(p.join(root, 'userdata', 'shared_preferences.json')).writeAsString(jsonEncode({'flutter.rommBaseUrl': 'x'}));
      await io.Directory(p.join(support, 'Emulators')).delete(recursive: true);
      await io.File(p.join(root, 'userdata', 'support', 'Emulators', 'e.exe')).create(recursive: true);

      await migration().toInstalled(includeDefaultFolders: false);

      final prefs = json(p.join(support, 'shared_preferences.json'));
      expect(prefs.containsKey('flutter.romsRootPath'), isFalse, reason: "the PC's own ROMs folder is the default");
      expect(prefs['flutter.emulatorsRootPath'], p.join(root, 'userdata', 'support', 'Emulators'));
    });

    test('a failure restores the PC data and keeps the marker', () async {
      // The support folder's parent is a file, so copying into it fails after
      // the Hive file in Documents has already been renamed aside.
      await io.File(p.join(tmp.path, 'blocked')).writeAsString('');
      final blocked = PortableMigration(
          root: root,
          installedSupportDir: p.join(tmp.path, 'blocked', 'freegosy'),
          installedDocumentsDir: documents,
          now: () => DateTime(2026, 10, 5, 12));

      await expectLater(blocked.toInstalled(includeDefaultFolders: false), throwsA(isA<io.FileSystemException>()));

      expect(io.File(blocked.markerPath).existsSync(), isTrue);
      expect(io.File(p.join(documents, 'freegosy_backups.hive')).readAsStringSync(), 'hive', reason: 'renamed back');
      expect(io.Directory(documents).listSync().where((e) => e.path.contains('before-portable')), isEmpty);
    });
  });

  test('installedDataModified is the installed settings file time, null when absent', () async {
    final prefs = io.File(p.join(support, 'shared_preferences.json'));
    final when = DateTime(2026, 3, 4, 5, 6, 7);
    await prefs.setLastModified(when);
    expect(migration().installedDataModified, when);
    await prefs.delete();
    expect(migration().installedDataModified, isNull);
  });

  test('defaultFoldersSize counts ROMs and Emulators', () async {
    await io.File(p.join(support, 'ROMs', 'big.bin')).writeAsBytes(List.filled(1000, 0));
    expect(await migration().defaultFoldersSize(portable: false), greaterThanOrEqualTo(1000));
  });
}
