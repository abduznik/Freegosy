import 'package:flutter/foundation.dart';

import '../formats/save_format_registry.dart';
import 'save_entry.dart';
import 'save_maker.dart';

/// How a save fits the emulator it would be played in.
enum SaveFitKind {
  /// In that emulator's format already.
  native,

  /// Converted to that emulator's format when played.
  converted,

  /// Who made it can't be told; restored as it is (converted by content when
  /// a format recognises it).
  unknownMaker,

  /// No installed emulator can use it.
  unusable,
}

@immutable
class SaveFit {
  const SaveFit(this.kind, {this.playsIn, this.reason});

  final SaveFitKind kind;

  /// The emulator it would be played in; null when unusable.
  final SaveMaker? playsIn;

  /// Why it is unusable.
  final String? reason;

  bool get usable => kind != SaveFitKind.unusable;
}

/// How [entry] fits for a game on [platformSlug] when [picked] is the
/// chosen emulator (null: "Any", each save plays in the emulator that made
/// it when [installed] holds it, else in [platformDefault]).
SaveFit fitFor(
  SaveEntry entry, {
  required String platformSlug,
  required SaveMaker? picked,
  required SaveMaker? platformDefault,
  required Set<String> installed,
  List<SaveSystem<Object>>? systems,
}) {
  final maker = entry.maker;
  final target = picked ?? (maker != null && installed.contains(maker.emulatorId) ? maker : platformDefault);
  if (target == null) {
    return const SaveFit(SaveFitKind.unusable, reason: 'No emulator for this platform is installed');
  }
  if (maker == null) return SaveFit(SaveFitKind.unknownMaker, playsIn: target);

  // A save on this PC stays with the core that made it: RetroArch keeps one
  // folder per core, and nothing copies a save between them.
  // A RetroArch backup made before its core was recorded goes back into
  // RetroArch with whichever core is picked.
  final coreUnknownBackup = entry.source == SaveSource.backup && maker.coreId == null;
  if (entry.source != SaveSource.romm &&
      maker.emulatorId == target.emulatorId &&
      maker.coreId != target.coreId &&
      !coreUnknownBackup) {
    return SaveFit(SaveFitKind.unusable,
        reason: 'This save belongs to the ${maker.coreId ?? 'default'} core; pick that core to play it');
  }
  // A backup is restored as it was zipped, unconverted.
  if (entry.source == SaveSource.backup && maker.emulatorId != target.emulatorId) {
    return SaveFit(SaveFitKind.unusable, reason: 'A backup goes back only into ${maker.emulatorId}');
  }

  // RetroArch uploads a save under its bare core name, which for some cores
  // is also a standalone emulator's id (mgba, melonds, pcsx2…): RomM can't
  // say which made it, so it fits both, as the pull always restored it.
  if (entry.source == SaveSource.romm && maker.tag == target.tag) {
    return SaveFit(SaveFitKind.native, playsIn: target);
  }

  final system = saveSystemFor(platformSlug, systems: systems);
  final makerFormat = system?.formatForTag(maker.tag);
  final targetFormat = system?.formatForTag(target.tag);

  // A raw system lists the emulators verified to keep the same bytes; a save
  // from any other (e.g. DeSmuME's into melonDS) doesn't fit it.
  if (makerFormat == null && targetFormat != null && targetFormat.byTagOnly) {
    return SaveFit(SaveFitKind.unusable, reason: "${maker.tag} saves can't be used by ${target.tag}");
  }

  if (maker.emulatorId == target.emulatorId) {
    // Cores of one emulator share a format unless the formats say otherwise.
    final differs = makerFormat != null && targetFormat != null && makerFormat != targetFormat;
    return SaveFit(differs ? SaveFitKind.converted : SaveFitKind.native, playsIn: target);
  }
  if (targetFormat != null) {
    return SaveFit(makerFormat == targetFormat ? SaveFitKind.native : SaveFitKind.converted, playsIn: target);
  }
  return SaveFit(SaveFitKind.unusable,
      reason: "${maker.emulatorId} saves can't be used by ${target.emulatorId}");
}
