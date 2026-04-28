import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'backup_entry.dart';

/// Hive-backed repository that persists up to [_maxBackups] local backup
/// entries per game ROM. Business logic (rotation, disk cleanup) lives here
/// so that providers stay thin.
class BackupRepository {
  static const String _boxName = 'freegosy_backups';
  static const int _maxBackups = 8;

  Box<List>? _box;

  /// Links the repository to the already-opened Hive box.
  void initBox() {
    if (_box != null && _box!.isOpen) return;
    _box = Hive.box<List>(_boxName);
  }

  Box<List> get _openBox {
    assert(_box != null && _box!.isOpen, 'BackupRepository: call initBox() first');
    return _box!;
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns the backup list for [romId], newest-first.
  List<BackupEntry> getEntries(String romId) {
    final raw = _openBox.get(romId);
    if (raw == null) return [];
    return raw.cast<BackupEntry>().toList();
  }

  /// Returns all unsynced entries across all games, along with their romId.
  List<({String romId, BackupEntry entry})> getUnsyncedEntries() {
    final unsynced = <({String romId, BackupEntry entry})>[];
    for (final key in _openBox.keys) {
      final romId = key.toString();
      final entries = getEntries(romId);
      for (final entry in entries) {
        if (!entry.isSynced) {
          unsynced.add((romId: romId, entry: entry));
        }
      }
    }
    // Sort oldest first so they get processed in order of creation
    unsynced.sort((a, b) => a.entry.timestamp.compareTo(b.entry.timestamp));
    return unsynced;
  }

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Appends [entry] for [romId]. If the list would exceed [_maxBackups], the
  /// oldest entry is silently deleted from disk and removed from the DB.
  Future<void> addEntry(String romId, BackupEntry entry) async {
    final entries = getEntries(romId);
    entries.insert(0, entry); // newest first

    if (entries.length > _maxBackups) {
      final overflow = entries.sublist(_maxBackups);
      entries.removeRange(_maxBackups, entries.length);
      for (final old in overflow) {
        await _deleteFile(old.localZipPath);
      }
    }

    await _openBox.put(romId, entries);
  }

  /// Removes a specific [entry] for [romId] and deletes its physical ZIP.
  Future<void> removeEntry(String romId, BackupEntry entry) async {
    final entries = getEntries(romId);
    entries.removeWhere((e) =>
        e.localZipPath == entry.localZipPath &&
        e.timestamp == entry.timestamp);
    await _openBox.put(romId, entries);
    await _deleteFile(entry.localZipPath);
  }

  /// Marks a specific [entry] as synced.
  Future<void> markAsSynced(String romId, BackupEntry entry) async {
    final entries = getEntries(romId);
    final index = entries.indexWhere((e) =>
        e.localZipPath == entry.localZipPath &&
        e.timestamp == entry.timestamp);
    if (index != -1) {
      final old = entries[index];
      entries[index] = BackupEntry(
        timestamp: old.timestamp,
        md5Hash: old.md5Hash,
        localZipPath: old.localZipPath,
        isSynced: true,
      );
      await _openBox.put(romId, entries);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<void> _deleteFile(String path) async {
    try {
      final file = io.File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[BackupRepository] Could not delete backup file: $path ($e)');
    }
  }
}
