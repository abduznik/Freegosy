import 'package:flutter/foundation.dart';

import '../resume_service.dart';
import 'play_choice.dart' as choice;
import 'play_choice.dart' show PlayItem, PlayPrompt, SavePlay, StatePlay;
import 'save_catalog.dart';
import 'save_entry.dart';
import 'save_fit.dart';
import 'save_maker.dart';

/// A save row: the save and how it fits the emulator it would play in.
@immutable
class PlayRow {
  const PlayRow(this.entry, this.fit, {this.sameAsLocal = false});
  final SaveEntry entry;
  final SaveFit fit;

  /// A RomM save that is the same as a save on this PC (its content_hash, or
  /// the RomM save this PC last synced it with).
  final bool sameAsLocal;
  SavePlay get item => SavePlay(entry, fit);
}

/// A RomM save group as shown: its newest shown version and older ones.
@immutable
class PlayRommGroup {
  const PlayRommGroup(this.group, this.newest, this.older);
  final RommSaveGroup group;
  final PlayRow newest;
  final List<PlayRow> older;
}

/// What the play screen and the Saves tab show for one emulator choice.
@immutable
class PlayView {
  const PlayView({
    required this.thisPc,
    required this.backups,
    required this.romm,
    required this.states,
    required this.hidden,
    required this.rommOffline,
    required this.preselected,
  });

  final List<PlayRow> thisPc;
  final List<PlayRow> backups;
  final List<PlayRommGroup> romm;
  final List<ResumeEntry> states;

  /// Saves left out because the picked emulator can't use them.
  final int hidden;
  final bool rommOffline;
  final PlayItem? preselected;

  List<PlayRow> get saveRows => [
        ...thisPc,
        ...backups,
        for (final g in romm) ...[g.newest, ...g.older],
      ];

  /// When [target]'s own save on this PC was made; null when it has none.
  DateTime? newestLocalFor(SaveMaker target) {
    DateTime? newest;
    for (final r in thisPc) {
      if (r.entry.maker != target) continue;
      if (newest == null || r.entry.savedAt.isAfter(newest)) newest = r.entry.savedAt;
    }
    return newest;
  }

  /// When the newest save that can be played was made.
  /// Backups don't count: their time is when the copy was made, not when
  /// the game saved. Nor RomM's copy of a save on this PC: it is dated by
  /// its upload, after the session.
  DateTime? get newestSave {
    DateTime? newest;
    for (final r in saveRows) {
      if (!r.fit.usable || r.entry.source == SaveSource.backup || r.sameAsLocal) continue;
      if (newest == null || r.entry.savedAt.isAfter(newest)) newest = r.entry.savedAt;
    }
    return newest;
  }

  /// Whether the save on this PC [local] is on RomM: this PC uploaded it as
  /// it is now (also when RomM has since pruned that upload: autocleanup
  /// keeps a slot's last few), or one of RomM's saves has its content
  /// (content_hash).
  bool isOnRomm(SaveEntry local) {
    if (local.sameAsRommId != null) return true;
    for (final g in romm) {
      for (final r in [g.newest, ...g.older]) {
        if (_holds(local, r.entry)) return true;
      }
    }
    return false;
  }

  /// A row for a card shared by every game with nothing of this game on it
  /// (no content to hash): no save of its own to lose.
  static bool _emptyCard(SaveEntry local) => local.sharedFile && local.contentHashes.isEmpty;

  /// The question to ask before starting [item] (see play_choice.promptFor).
  PlayPrompt? promptFor(PlayItem item) {
    switch (item) {
      case SavePlay(:final entry, :final fit):
        final target = fit.playsIn;
        if (target == null) return null;
        // Replacing the target's own save on this PC that RomM doesn't have:
        // its progress would only survive in a backup.
        final replaces = !(entry.source == SaveSource.local && entry.maker == target);
        if (replaces && thisPc.any((r) => r.entry.maker == target && !_emptyCard(r.entry) && !isOnRomm(r.entry))) {
          return PlayPrompt.notOnRomm;
        }
        return choice.promptFor(item, newestLocalOfTarget: newestLocalFor(target));
      case StatePlay():
        return choice.promptFor(item, newestSave: newestSave);
    }
  }
}

/// The rows for [catalog] and [states] when [picked] is the chosen emulator
/// (null: Any). With an emulator picked, saves it can't use are left out and
/// counted, unless [showAll].
PlayView buildPlayView({
  required SaveCatalog catalog,
  required List<ResumeEntry> states,
  required String platformSlug,
  required SaveMaker? picked,
  required SaveMaker? platformDefault,
  required Set<String> installed,
  bool showAll = false,
}) {
  var hidden = 0;
  List<PlayRow> keep(Iterable<SaveEntry> entries) {
    final rows = <PlayRow>[];
    for (final e in entries) {
      final r = PlayRow(
          e, fitFor(e, platformSlug: platformSlug, picked: picked, platformDefault: platformDefault, installed: installed));
      if (r.fit.usable || picked == null || showAll) {
        rows.add(r);
      } else {
        hidden++;
      }
    }
    return rows;
  }

  final thisPc = keep(catalog.thisPc);
  final backups = keep(catalog.backups);

  // RomM's copy of a usable save on this PC: the same content_hash, or the
  // RomM save this PC last synced it with. It is dated when it was uploaded,
  // after the session that made it, so the save on this PC is the one to
  // start with. (Not from an unusable row: its copy may still be usable.)
  final localHashes = {
    for (final r in thisPc)
      if (r.fit.usable) ...r.entry.contentHashes,
  };
  final localCopyIds = {
    for (final r in thisPc)
      if (r.fit.usable && r.entry.sameAsRommId != null) r.entry.sameAsRommId!,
  };
  bool isCopy(SaveEntry e) {
    final save = e.rommSave;
    if (save == null) return false;
    final hash = save['content_hash']?.toString();
    return (hash != null && localHashes.contains(hash)) || localCopyIds.contains(save['id']?.toString());
  }

  PlayRow marked(PlayRow r) => isCopy(r.entry) ? PlayRow(r.entry, r.fit, sameAsLocal: true) : r;
  final romm = <PlayRommGroup>[];
  for (final g in catalog.romm) {
    final rows = keep([g.newest, ...g.older]).map(marked).toList();
    if (rows.isNotEmpty) romm.add(PlayRommGroup(g, rows.first, rows.sublist(1)));
  }
  final shownStates = picked == null ? states : [for (final s in states) if (s.emulatorId == picked.emulatorId) s];
  final rommRows = [for (final g in romm) ...[g.newest, ...g.older]];
  // A save on a shared card is dated by the card, which any game on it
  // changes. With a usable RomM save, it stands in with its RomM copy's
  // time, or not at all when RomM has no copy of it.
  final rommUsable = rommRows.any((r) => r.fit.usable);
  final standIns = <PlayItem, PlayItem>{};
  // Not backups: a backup is a copy, dated when it was made, never the save
  // to start with unless chosen.
  final saves = <SavePlay>[];
  for (final r in thisPc) {
    if (!r.entry.sharedFile || !rommUsable) {
      saves.add(r.item);
      continue;
    }
    PlayRow? copy;
    for (final c in rommRows) {
      if (c.sameAsLocal && _holds(r.entry, c.entry) && (copy == null || c.entry.savedAt.isAfter(copy.entry.savedAt))) {
        copy = c;
      }
    }
    if (copy != null) {
      final item = copy.item;
      saves.add(item);
      standIns[item] = r.item;
    }
  }
  saves.addAll([for (final r in rommRows) if (!r.sameAsLocal) r.item]);
  final pre = choice.preselect(saves, [for (final s in shownStates) StatePlay(s)]);
  return PlayView(
    thisPc: thisPc,
    backups: backups,
    romm: romm,
    states: shownStates,
    hidden: hidden,
    rommOffline: catalog.rommOffline,
    preselected: standIns[pre] ?? pre,
  );
}

/// Whether RomM's save [romm] holds exactly the local save [local]: its
/// content_hash, or the RomM save this PC last synced it with.
bool _holds(SaveEntry local, SaveEntry romm) {
  final hash = romm.rommSave?['content_hash']?.toString();
  return (hash != null && local.contentHashes.contains(hash)) ||
      (local.sameAsRommId != null && local.sameAsRommId == romm.rommSave?['id']?.toString());
}
