import 'dart:math' as math;

/// Which slot a save state is, as far as the emulator's naming tells.
sealed class StateSlot {
  const StateSlot();

  /// How the slot reads in the resume list.
  String get label;
}

/// The emulator's automatic slot (resume-on-exit / auto-save).
final class AutoStateSlot extends StateSlot {
  const AutoStateSlot();
  @override
  String get label => 'Resume (saved on exit)';
  @override
  bool operator ==(Object other) => other is AutoStateSlot;
  @override
  int get hashCode => (AutoStateSlot).hashCode;
}

/// A numbered quick-save slot.
final class NumberedStateSlot extends StateSlot {
  const NumberedStateSlot(this.number);
  final int number;
  @override
  String get label => 'Slot $number';
  @override
  bool operator ==(Object other) => other is NumberedStateSlot && other.number == number;
  @override
  int get hashCode => Object.hash(NumberedStateSlot, number);
}

/// A state whose slot the emulator's naming does not reveal.
final class UnknownStateSlot extends StateSlot {
  const UnknownStateSlot(this.name);
  final String name;
  @override
  String get label => name;
  @override
  bool operator ==(Object other) => other is UnknownStateSlot && other.name == name;
  @override
  int get hashCode => Object.hash(UnknownStateSlot, name);
}

/// What a state file records about itself.
class StateFileInfo {
  const StateFileInfo({required this.savedAt, this.emulatorVersion, this.formatId});

  final DateTime savedAt;

  /// The emulator build that wrote the state, as the emulator prints it
  /// (e.g. `v2.8.2`), or null when the format doesn't record it.
  final String? emulatorVersion;

  /// The emulator's internal state-format id, recorded for future strict
  /// checks. Not used for decisions yet.
  final String? formatId;
}

/// Whether a state is expected to load in the installed emulator.
enum StateCompat { ok, mismatch, unknown }

final _versionPattern = RegExp(r'^[vV]?(\d+(?:\.\d+)*)(.*)$');

/// Whether a state written by emulator build [a] is expected to load in build
/// [b]. Versions made of dotted numbers compare numerically, ignoring a leading
/// `v` and missing trailing parts (`v2.8.2` is `2.8.2.0`): different numbers
/// are a [StateCompat.mismatch]. Equal numbers where either side carries a
/// suffix (a nightly or self-built `v2.3.72-12-gabcdef` next to the exe's
/// `2.3.72.0`) are [StateCompat.unknown]: a nightly can't be told from the
/// release. The very same text is always [StateCompat.ok]; any other
/// non-numeric pair is a mismatch.
StateCompat compareEmulatorVersions(String a, String b) {
  final x = a.trim();
  final y = b.trim();
  if (x == y) return StateCompat.ok;
  final mx = _versionPattern.firstMatch(x);
  final my = _versionPattern.firstMatch(y);
  if (mx == null || my == null) return StateCompat.mismatch;
  final px = mx.group(1)!.split('.').map(int.parse).toList();
  final py = my.group(1)!.split('.').map(int.parse).toList();
  for (var i = 0; i < math.max(px.length, py.length); i++) {
    if ((i < px.length ? px[i] : 0) != (i < py.length ? py[i] : 0)) return StateCompat.mismatch;
  }
  return mx.group(2)!.isEmpty && my.group(2)!.isEmpty ? StateCompat.ok : StateCompat.unknown;
}

/// True when [a] and [b] are known to name the same emulator build (see
/// [compareEmulatorVersions]).
bool sameEmulatorVersion(String a, String b) => compareEmulatorVersions(a, b) == StateCompat.ok;

/// [StateCompat.unknown] when either version is unknown, otherwise
/// [compareEmulatorVersions].
StateCompat compatOf(String? stateVersion, String? installedVersion) {
  if (stateVersion == null || installedVersion == null) return StateCompat.unknown;
  return compareEmulatorVersions(stateVersion, installedVersion);
}
