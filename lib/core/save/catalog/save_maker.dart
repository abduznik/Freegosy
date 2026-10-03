import 'package:flutter/foundation.dart';

import '../../emulator/emulator_registry_data.dart';
import '../../emulator/retroarch_core_list.dart';

/// Who made a save: a Freegosy emulator and, for RetroArch, the core.
@immutable
class SaveMaker {
  const SaveMaker(this.emulatorId, {this.coreId});

  final String emulatorId;

  /// The RetroArch core without `_libretro` (e.g. `mupen64plus_next`); null
  /// for any other emulator, or RetroArch with an unknown core.
  final String? coreId;

  /// The RomM `emulator` tag Freegosy uploads this maker's saves with (see
  /// SaveSyncService._saveEmulatorTag) and the save formats are keyed by.
  String get tag => coreId ?? emulatorId;

  @override
  bool operator ==(Object other) => other is SaveMaker && other.emulatorId == emulatorId && other.coreId == coreId;

  @override
  int get hashCode => Object.hash(emulatorId, coreId);

  @override
  String toString() => coreId == null ? emulatorId : '$emulatorId/$coreId';
}

/// Every emulator id Freegosy knows.
Set<String> get kKnownEmulatorIds => {for (final def in kEmulatorDefinitions) def['id'] as String};

String _stripLibretro(String id) => id.replaceAll(RegExp(r'_libretro$'), '');

/// [core] as a SaveMaker's coreId: `mgba` for `mgba`, `mgba_libretro` and
/// `mgba_libretro.dll`; null for null.
String? bareCoreId(String? core) =>
    core == null ? null : _stripLibretro(core.replaceAll(RegExp(r'\.(dll|so|dylib)$'), ''));

/// The maker of a save RomM tagged [tag]; null when it can't be told
/// (`freegosy`, empty, or a name Freegosy doesn't know). A name that is both
/// a standalone emulator and a RetroArch core (`mgba`) is the standalone
/// emulator: Freegosy uploads that emulator's saves under its id.
SaveMaker? resolveSaveMaker(String? tag, {required Set<String> emulatorIds}) {
  final t = tag?.trim().toLowerCase() ?? '';
  if (t.isEmpty || t == 'freegosy' || t == 'retroarch') return null;
  if (emulatorIds.contains(t)) return SaveMaker(t);
  final core = _stripLibretro(t);
  for (final c in kRetroArchCores) {
    if (_stripLibretro(c.id) == core) return SaveMaker('retroarch', coreId: core);
  }
  return null;
}
