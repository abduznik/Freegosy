import 'package:flutter/foundation.dart';

import 'save_entry.dart';

/// Versions of one RomM save (same slot and tag), newest first.
@immutable
class RommSaveGroup {
  const RommSaveGroup({required this.slot, required this.tag, required this.newest, required this.older});
  final String slot;
  final String tag;
  final SaveEntry newest;
  final List<SaveEntry> older;
}

/// Every save of one game, as the play screen and the Saves tab list them.
@immutable
class SaveCatalog {
  const SaveCatalog({required this.thisPc, required this.backups, required this.romm, required this.rommOffline});

  /// One row per installed emulator that has a save for the game, newest first.
  final List<SaveEntry> thisPc;

  /// Local backups, newest first.
  final List<SaveEntry> backups;

  /// RomM saves, the group with the newest save first.
  final List<RommSaveGroup> romm;

  /// RomM couldn't be listed (offline or failing).
  final bool rommOffline;

  List<SaveEntry> get all => [
        ...thisPc,
        ...backups,
        for (final g in romm) ...[g.newest, ...g.older],
      ];
}

int _newestFirst(SaveEntry a, SaveEntry b) => b.savedAt.compareTo(a.savedAt);

/// [romm] null: RomM couldn't be listed.
SaveCatalog buildSaveCatalog({
  required List<SaveEntry> local,
  required List<SaveEntry> backups,
  required List<SaveEntry>? romm,
}) {
  final groups = <String, List<SaveEntry>>{};
  for (final e in romm ?? const <SaveEntry>[]) {
    groups.putIfAbsent(e.groupKey, () => []).add(e);
  }
  final rommGroups = [
    for (final versions in groups.values)
      () {
        final sorted = [...versions]..sort(_newestFirst);
        return RommSaveGroup(
          slot: sorted.first.slot ?? '',
          tag: sorted.first.tag ?? '',
          newest: sorted.first,
          older: sorted.sublist(1),
        );
      }(),
  ]..sort((a, b) => _newestFirst(a.newest, b.newest));
  return SaveCatalog(
    thisPc: [...local]..sort(_newestFirst),
    backups: [...backups]..sort(_newestFirst),
    romm: rommGroups,
    rommOffline: romm == null,
  );
}
