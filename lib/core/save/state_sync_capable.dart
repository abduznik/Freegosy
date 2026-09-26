import 'dart:io' as io;
import 'dart:typed_data';
import '../romm/romm_models.dart';
import 'save_state_info.dart';
import 'save_strategy.dart';

/// Implemented by a [SaveStrategy] whose emulator's save states can be synced
/// through RomM's `/api/states` (see StateSyncService).
///
/// The strategy only answers *where* an emulator keeps a game's states and
/// *which* file names belong to the game. Hashing, transfers, safe writes and
/// conflict handling live in StateSyncService so every emulator gets the same
/// behaviour.
mixin StateSyncCapable on SaveStrategy {
  /// Directory holding [game]'s state files. May throw if the emulator's data
  /// folder cannot be resolved; the caller treats that as "skip state sync".
  Future<String> stateDirectory(Game game, String romPath);

  /// Predicate telling whether a state file name — local or from the server —
  /// belongs to [game], or null if the game cannot be identified (for example
  /// its serial could not be read from the ROM). It must reject names that
  /// contain path separators and backup/temp files.
  Future<bool Function(String fileName)?> stateFileMatcher(
      Game game, String romPath);

  /// Sanity check applied to bytes downloaded from RomM before they replace a
  /// local state. The default only rejects empty content.
  bool looksLikeValidState(Uint8List bytes) => bytes.isNotEmpty;

  /// Which slot [fileName] is. Works on names only (RomM-only states too).
  StateSlot slotOf(String fileName) => UnknownStateSlot(fileName);

  /// What [file] records about itself. Must never throw: an unreadable file
  /// yields its modified time (or the epoch) and no version.
  Future<StateFileInfo> describeState(io.File file) async {
    try {
      return StateFileInfo(savedAt: await file.lastModified());
    } catch (_) {
      return StateFileInfo(savedAt: DateTime.fromMillisecondsSinceEpoch(0));
    }
  }

  /// Thumbnail bytes for [file] (embedded or a sidecar), or null when there is
  /// none or reading fails. Must never throw.
  Future<Uint8List?> stateScreenshot(io.File file) async => null;
}
