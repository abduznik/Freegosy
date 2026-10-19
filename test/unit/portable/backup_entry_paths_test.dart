import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/portable/portable_paths.dart';
import 'package:freegosy/core/save/backup_entry.dart';
import 'package:hive/hive.dart';

void main() {
  late io.Directory dir;
  setUpAll(() => Hive.registerAdapter(BackupEntryAdapter()));
  setUp(() async {
    dir = await io.Directory.systemTemp.createTemp('backup_paths');
    Hive.init(dir.path);
  });
  tearDown(() async {
    PortablePaths.active = null;
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('a portable copy stores backup zip paths relative and reads them back absolute', () async {
    PortablePaths.active = PortablePaths(root: r'E:\Freegosy', exists: (_) => true);
    final box = await Hive.openBox<List>('b');
    final entry = BackupEntry(
        timestamp: DateTime(2026), md5Hash: 'h', localZipPath: r'E:\Freegosy\data\support\backups\1\a.zip');
    await box.put('1', [entry]);
    await box.close();

    PortablePaths.active = PortablePaths(root: r'F:\Freegosy', exists: (_) => true);
    final reopened = await Hive.openBox<List>('b');
    expect((reopened.get('1')!.single as BackupEntry).localZipPath, r'F:\Freegosy\data\support\backups\1\a.zip');
  });
}
