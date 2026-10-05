import '../resume_service.dart';
import 'save_entry.dart';
import 'save_fit.dart';

/// Something the play screen can start: a save, or a state to resume.
sealed class PlayItem {
  const PlayItem();
  DateTime get time;
}

final class SavePlay extends PlayItem {
  const SavePlay(this.entry, this.fit);
  final SaveEntry entry;
  final SaveFit fit;
  @override
  DateTime get time => entry.savedAt;
}

final class StatePlay extends PlayItem {
  const StatePlay(this.entry);
  final ResumeEntry entry;
  @override
  DateTime get time => entry.savedAt;
}

/// What the play screen starts on: the newest usable save, or a state when
/// it is newer still (a state carries the game's save memory, so an older
/// one would roll the save back); null when there is neither.
PlayItem? preselect(List<SavePlay> saves, List<StatePlay> states) {
  SavePlay? newestSave;
  for (final s in saves) {
    if (s.fit.usable && (newestSave == null || s.time.isAfter(newestSave.time))) newestSave = s;
  }
  StatePlay? newestState;
  for (final s in states) {
    if (newestState == null || s.time.isAfter(newestState.time)) newestState = s;
  }
  if (newestState != null && (newestSave == null || newestState.time.isAfter(newestSave.time))) {
    return newestState;
  }
  return newestSave;
}

/// Why playing [chosen] needs asking first.
enum PlayPrompt {
  /// The save would replace a newer local save of the emulator it plays in.
  olderSave,

  /// The state is older than the newest save and may roll it back.
  olderState,

  /// The save would replace a save on this PC that isn't on RomM (changed
  /// since its last upload, e.g. played offline): whatever its time, ask.
  notOnRomm,
}

/// The question to ask before playing [chosen], or null to play straight
/// away. [newestLocalOfTarget]: when the newest local save of the emulator
/// it plays in was made. [newestSave]: the newest save of any kind.
PlayPrompt? promptFor(PlayItem chosen, {DateTime? newestLocalOfTarget, DateTime? newestSave}) {
  switch (chosen) {
    case SavePlay(:final time):
      if (newestLocalOfTarget != null && time.isBefore(newestLocalOfTarget)) return PlayPrompt.olderSave;
      return null;
    case StatePlay(:final time):
      if (newestSave != null && time.isBefore(newestSave)) return PlayPrompt.olderState;
      return null;
  }
}
