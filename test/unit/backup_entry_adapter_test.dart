import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/backup_entry.dart';
import 'package:hive/hive.dart';
// ignore: implementation_imports
import 'package:hive/src/binary/binary_reader_impl.dart';
// ignore: implementation_imports
import 'package:hive/src/binary/binary_writer_impl.dart';

/// Round-trips through the adapter with Hive's in-memory binary writer/reader.
BackupEntry roundTrip(BackupEntry entry, {bool asOldRecord = false}) {
  final writer = BinaryWriterImpl(Hive);
  if (asOldRecord) {
    // What versions before emulatorId wrote: four fields.
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(entry.timestamp)
      ..writeByte(1)
      ..write(entry.md5Hash)
      ..writeByte(2)
      ..write(entry.localZipPath)
      ..writeByte(3)
      ..write(entry.isSynced);
  } else {
    BackupEntryAdapter().write(writer, entry);
  }
  return BackupEntryAdapter().read(BinaryReaderImpl(writer.toBytes(), Hive));
}

void main() {
  final when = DateTime(2026, 10, 1, 9, 56);

  test('a backup keeps the emulator it was made for', () {
    final read = roundTrip(BackupEntry(timestamp: when, md5Hash: 'abc', localZipPath: '/b/x.zip', emulatorId: 'ares'));
    expect(read.emulatorId, 'ares');
    expect(read.localZipPath, '/b/x.zip');
  });

  test('a backup written before emulatorId still reads, with no emulator', () {
    final read = roundTrip(BackupEntry(timestamp: when, md5Hash: 'abc', localZipPath: '/b/x.zip'), asOldRecord: true);
    expect(read.emulatorId, isNull);
    expect(read.timestamp, when);
  });

  test('a RetroArch backup keeps its core', () {
    final read = roundTrip(
        BackupEntry(timestamp: when, md5Hash: 'abc', localZipPath: '/b/x.zip', emulatorId: 'retroarch', coreId: 'mgba'));
    expect(read.emulatorId, 'retroarch');
    expect(read.coreId, 'mgba');
  });

  test('a backup written before coreId reads with no core', () {
    final read = roundTrip(BackupEntry(timestamp: when, md5Hash: 'abc', localZipPath: '/b/x.zip', emulatorId: 'ares'));
    expect(read.coreId, isNull);
  });
}
