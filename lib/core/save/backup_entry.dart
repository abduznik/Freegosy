import 'package:hive/hive.dart';

/// A single local save backup checkpoint for a game.
class BackupEntry {
  final DateTime timestamp;
  final String md5Hash;
  final String localZipPath;
  final bool isSynced;

  BackupEntry({
    required this.timestamp,
    required this.md5Hash,
    required this.localZipPath,
    this.isSynced = false,
  });
}

// ---------------------------------------------------------------------------
// Hand-written TypeAdapter (avoids needing build_runner / code-gen)
// ---------------------------------------------------------------------------

class BackupEntryAdapter extends TypeAdapter<BackupEntry> {
  @override
  final int typeId = 1;

  @override
  BackupEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final key = reader.readByte();
      final value = reader.read();
      fields[key] = value;
    }
    return BackupEntry(
      timestamp: fields[0] as DateTime,
      md5Hash: fields[1] as String,
      localZipPath: fields[2] as String,
      isSynced: fields.containsKey(3) ? fields[3] as bool : true,
    );
  }

  @override
  void write(BinaryWriter writer, BackupEntry obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.timestamp)
      ..writeByte(1)
      ..write(obj.md5Hash)
      ..writeByte(2)
      ..write(obj.localZipPath)
      ..writeByte(3)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
