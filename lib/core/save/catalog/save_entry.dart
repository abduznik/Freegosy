import 'package:flutter/foundation.dart';

import '../backup_entry.dart';
import 'save_maker.dart';

/// Where a save row comes from.
enum SaveSource { local, backup, romm }

/// One save the user can look at, restore or play.
@immutable
class SaveEntry {
  const SaveEntry({
    required this.source,
    required this.fileName,
    required this.savedAt,
    this.maker,
    this.tag,
    this.sizeBytes,
    this.slot,
    this.rommSave,
    this.backup,
    this.sameAsRommId,
    this.contentHashes = const {},
    this.sharedFile = false,
  });

  /// A save from RomM's save list ([save] is the list item as RomM sent it).
  factory SaveEntry.fromRomm(Map<String, dynamic> save, {required Set<String> emulatorIds}) {
    final tag = save['emulator']?.toString();
    final time = DateTime.tryParse(save['updated_at']?.toString() ?? '') ??
        DateTime.tryParse(save['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final size = save['file_size_bytes'];
    return SaveEntry(
      source: SaveSource.romm,
      fileName: save['file_name']?.toString() ?? '',
      savedAt: time.toLocal(),
      maker: resolveSaveMaker(tag, emulatorIds: emulatorIds),
      tag: tag,
      sizeBytes: size is int ? size : int.tryParse(size?.toString() ?? ''),
      slot: save['slot']?.toString(),
      rommSave: save,
    );
  }

  final SaveSource source;
  final String fileName;
  final DateTime savedAt;

  /// Who made it; null when that can't be told.
  final SaveMaker? maker;

  /// The tag shown on the row: RomM's `emulator`, or the maker's tag for a
  /// save on this PC.
  final String? tag;
  final int? sizeBytes;

  /// RomM's slot (RomM rows only).
  final String? slot;

  /// The RomM list item, for downloading (RomM rows only).
  final Map<String, dynamic>? rommSave;

  /// The backup (backup rows only).
  final BackupEntry? backup;

  /// The id of the RomM save that holds exactly this save, as this PC last
  /// synced it (local rows only); null when it changed since.
  final String? sameAsRommId;

  /// The `content_hash` RomM would give this save as each sync mode uploads
  /// it (local rows only; see SaveSyncService.rommHashOfLocal).
  final Set<String> contentHashes;

  /// The save is in a file other games share (a memory card): its time is
  /// the file's, which any game on it changes (local rows only).
  final bool sharedFile;

  /// RomM rows with the same key are versions of one save.
  String get groupKey => '${slot ?? ''}|${tag ?? ''}';
}
