import 'save_entry.dart';
import 'save_maker.dart';

/// What the play screen asks to start: [save] in [emulator] (null: the
/// emulator's own current save). [remember]: make [emulator] the game's
/// emulator, as the picker's "Remember" does.
class PlayRequest {
  const PlayRequest({required this.emulator, this.save, this.remember = false, this.forget = false, this.rommCopy});
  final SaveMaker emulator;
  final SaveEntry? save;
  final bool remember;

  /// Forget the game's remembered emulator ("Remember" turned off for it).
  final bool forget;

  /// RomM's copy of the save on this PC the game starts with (an item of
  /// RomM's save list), when the play screen recognised one: RomM is told
  /// this device has it (SaveSyncService.confirmRommCopy).
  final Map<String, dynamic>? rommCopy;
}
