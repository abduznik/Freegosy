import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/backup_entry.dart';
import 'package:freegosy/core/save/backup_repository.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('backup_repo_emulator');
    Hive.init(tmp.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(BackupEntryAdapter());
    await Hive.openBox<List>('freegosy_backups');
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('marking a backup synced keeps the emulator it was made for', () async {
    final repo = BackupRepository()..initBox();
    final entry = BackupEntry(timestamp: DateTime(2026, 10, 1), md5Hash: 'a', localZipPath: '${tmp.path}/a.zip', emulatorId: 'ares');
    await repo.addEntry('g', entry);

    await repo.markAsSynced('g', entry);

    final read = repo.getEntries('g').single;
    expect(read.isSynced, isTrue);
    expect(read.emulatorId, 'ares');
  });

  BackupEntry entryAt(int i, {String hash = 'h'}) {
    final zip = File('${tmp.path}/b$i.zip')..writeAsStringSync('$i');
    return BackupEntry(timestamp: DateTime(2026, 10, 1, i), md5Hash: '$hash$i', localZipPath: zip.path);
  }

  test('keeps the 8 newest backups of a game', () async {
    final repo = BackupRepository()..initBox();
    for (var i = 0; i < 10; i++) {
      await repo.addEntry('g', entryAt(i));
    }

    final kept = repo.getEntries('g');
    expect(kept.length, 8);
    expect(kept.last.md5Hash, 'h2');
    expect(File('${tmp.path}/b1.zip').existsSync(), isFalse);
  });

  test('a backup the same as the newest is not added, and its zip is deleted', () async {
    final repo = BackupRepository()..initBox();
    await repo.addEntry('g', entryAt(0));
    final same = entryAt(1);
    final unchanged = BackupEntry(timestamp: same.timestamp, md5Hash: 'h0', localZipPath: same.localZipPath);

    final added = await repo.addUnlessSameAsNewest('g', unchanged);

    expect(added, isFalse);
    expect(repo.getEntries('g').single.md5Hash, 'h0');
    expect(File(same.localZipPath).existsSync(), isFalse);
    expect(File('${tmp.path}/b0.zip').existsSync(), isTrue);
  });

  test('a changed backup is added', () async {
    final repo = BackupRepository()..initBox();
    await repo.addEntry('g', entryAt(0));

    final added = await repo.addUnlessSameAsNewest('g', entryAt(1));

    expect(added, isTrue);
    expect(repo.getEntries('g').length, 2);
  });
}
