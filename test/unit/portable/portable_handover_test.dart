import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/portable/portable_handover.dart';
import 'package:freegosy/core/save/backup_entry.dart';
import 'package:freegosy/core/storage/secret_store.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fake_retroachievements.dart' show InMemoryAppPreferences;

class _MapStore implements SecretStore {
  _MapStore([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
}

void main() {
  late io.Directory dir;
  late Box<List> backups;
  setUpAll(() => Hive.registerAdapter(BackupEntryAdapter()));
  setUp(() async {
    dir = await io.Directory.systemTemp.createTemp('handover');
    Hive.init(dir.path);
    backups = await Hive.openBox<List>('freegosy_backups');
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('pending credentials move from the stick into normal secure storage', () async {
    final credentialsDir = p.join(dir.path, 'userdata', 'credentials');
    await io.Directory(credentialsDir).create(recursive: true);
    final prefs = InMemoryAppPreferences()..setString(PortableHandover.pendingCredentialsKey, p.join(dir.path, 'userdata'));
    final platform = _MapStore();
    final onStick = _MapStore({'rommPassword': 'pw'});

    await PortableHandover.run(
        prefs: prefs, backups: backups, platformSecrets: platform, credentialsIn: (d) => onStick);

    expect(platform.values, {'rommPassword': 'pw'});
    expect(prefs.getString(PortableHandover.pendingCredentialsKey), isNull);
  });

  test('a stick that is gone clears the pending key and changes nothing', () async {
    final prefs = InMemoryAppPreferences()
      ..setString(PortableHandover.pendingCredentialsKey, p.join(dir.path, 'unplugged', 'userdata'));
    final platform = _MapStore();
    await PortableHandover.run(
        prefs: prefs, backups: backups, platformSecrets: platform, credentialsIn: (d) => _MapStore({'x': 'y'}));
    expect(platform.values, isEmpty);
    expect(prefs.getString(PortableHandover.pendingCredentialsKey), isNull);
  });

  test('imported secrets move from the copied platform file into the per-PC store', () async {
    final prefs = InMemoryAppPreferences()..setBool(PortableHandover.pendingImportSecretsKey, true);
    final copiedPlatformFile = _MapStore({'rommApiKey': 'k'});
    final perPc = _MapStore();
    await PortableHandover.run(
        prefs: prefs, backups: backups, platformSecrets: copiedPlatformFile, portableSecrets: perPc);
    expect(perPc.values, {'rommApiKey': 'k'});
    expect(copiedPlatformFile.values, isEmpty, reason: 'the copied file is emptied once handed over');
    expect(prefs.getBool(PortableHandover.pendingImportSecretsKey), isNull);
  });

  test('backup paths under the old folder are rebased; others are left alone', () async {
    await backups.put('1', [
      BackupEntry(timestamp: DateTime(2026), md5Hash: 'a', localZipPath: p.join('C:', 'old', 'backups', 'x.zip')),
      BackupEntry(timestamp: DateTime(2026), md5Hash: 'b', localZipPath: p.join('D:', 'elsewhere', 'y.zip'), isSynced: true),
    ]);
    final prefs = InMemoryAppPreferences()
      ..setString(PortableHandover.rebaseBackupsFromKey, p.join('C:', 'old'))
      ..setString(PortableHandover.rebaseBackupsToKey, p.join('E:', 'new'));

    await PortableHandover.run(prefs: prefs, backups: backups, platformSecrets: _MapStore());

    final entries = backups.get('1')!.cast<BackupEntry>();
    expect(entries[0].localZipPath, p.join('E:', 'new', 'backups', 'x.zip'));
    expect(entries[1].localZipPath, p.join('D:', 'elsewhere', 'y.zip'));
    expect(entries[1].isSynced, isTrue);
    expect(prefs.getString(PortableHandover.rebaseBackupsFromKey), isNull);
    expect(prefs.getString(PortableHandover.rebaseBackupsToKey), isNull);
  });

  test('a malformed backup box value does not stop the hand-over; keys are removed', () async {
    await backups.put('bad', ['not a BackupEntry']);
    final prefs = InMemoryAppPreferences()
      ..setString(PortableHandover.rebaseBackupsFromKey, p.join('C:', 'old'))
      ..setString(PortableHandover.rebaseBackupsToKey, p.join('E:', 'new'));
    await PortableHandover.run(prefs: prefs, backups: backups, platformSecrets: _MapStore());
    expect(prefs.getString(PortableHandover.rebaseBackupsFromKey), isNull);
    expect(prefs.getString(PortableHandover.rebaseBackupsToKey), isNull);
  });

  test('pending import flag is cleared even without a per-PC store', () async {
    final prefs = InMemoryAppPreferences()..setBool(PortableHandover.pendingImportSecretsKey, true);
    final platform = _MapStore({'k': 'v'});
    await PortableHandover.run(prefs: prefs, backups: backups, platformSecrets: platform);
    expect(prefs.getBool(PortableHandover.pendingImportSecretsKey), isNull);
    expect(platform.values, {'k': 'v'});
  });
}
