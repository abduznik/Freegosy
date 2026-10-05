import 'package:hive/hive.dart';

/// A single local save backup checkpoint for a game.
class BackupEntry {
  final DateTime timestamp;
  final String md5Hash;
  final String localZipPath;
  final bool isSynced;

  /// The emulator the backed-up save belongs to; null for backups made
  /// before this was recorded.
  final String? emulatorId;

  /// The RetroArch core (e.g. `mgba`) when [emulatorId] is RetroArch; null
  /// for another emulator, or a backup made before this was recorded.
  final String? coreId;

  BackupEntry({
    required this.timestamp,
    required this.md5Hash,
    required this.localZipPath,
    this.isSynced = false,
    this.emulatorId,
    this.coreId,
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
      emulatorId: fields.containsKey(4) ? fields[4] as String? : null,
      coreId: fields.containsKey(5) ? fields[5] as String? : null,
    );
  }

  @override
  void write(BinaryWriter writer, BackupEntry obj) {
    writer
      ..writeByte(4 + (obj.emulatorId == null ? 0 : 1) + (obj.coreId == null ? 0 : 1))
      ..writeByte(0)
      ..write(obj.timestamp)
      ..writeByte(1)
      ..write(obj.md5Hash)
      ..writeByte(2)
      ..write(obj.localZipPath)
      ..writeByte(3)
      ..write(obj.isSynced);
    if (obj.emulatorId != null) {
      writer
        ..writeByte(4)
        ..write(obj.emulatorId);
    }
    if (obj.coreId != null) {
      writer
        ..writeByte(5)
        ..write(obj.coreId);
    }
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
