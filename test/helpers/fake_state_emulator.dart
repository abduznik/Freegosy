import 'dart:io';
import 'dart:typed_data';
import 'package:freegosy/core/emulator/strategies/pcsx2_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/save_state_info.dart';
import 'package:freegosy/core/save/save_strategy.dart';
import 'package:freegosy/core/save/state_sync_capable.dart';
import 'package:path/path.dart' as p;

/// A made-up emulator "fakeemu" whose states are `GAME.auto.st` / `GAME.<n>.st`
/// and start with the text `ver=<version>\n`. Deliberately nothing like PCSX2,
/// so ResumeService tests prove the service is emulator-agnostic.
///
/// With [perDisc], a state belongs to one ROM file (like a disc's serial): the
/// matcher for `.../<disc>.iso` accepts only `GAME-<disc>.auto.st` and
/// `GAME-<disc>.<n>.st`.
class FakeStateSaveStrategy extends SaveStrategy with StateSyncCapable {
  FakeStateSaveStrategy(this.dir,
      {this.id = 'fakeemu', this.identifiable = true, this.perDisc = false});
  final String dir;
  final String id;
  bool identifiable;
  final bool perDisc;
  final Map<String, List<int>> screenshots = {};

  @override
  String get strategyId => id;
  @override
  Future<String?> getSaveDir(Game game, String romPath) async => null;
  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
          {DateTime? sessionStart, String syncMode = 'both'}) async => [];
  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async => false;
  @override
  Future<String> stateDirectory(Game game, String romPath) async => dir;
  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async =>
      !identifiable
          ? null
          : perDisc
              ? (name) => RegExp('^GAME-${RegExp.escape(p.basenameWithoutExtension(romPath))}'
                      r'\.(auto|\d+)\.st$')
                  .hasMatch(name)
              : (name) => RegExp(r'^GAME\.(auto|\d+)\.st$').hasMatch(name);
  @override
  StateSlot slotOf(String fileName) {
    final m = RegExp(r'^GAME(?:-[^.]+)?\.(auto|\d+)\.st$').firstMatch(fileName);
    if (m == null) return UnknownStateSlot(fileName);
    return m.group(1) == 'auto' ? const AutoStateSlot() : NumberedStateSlot(int.parse(m.group(1)!));
  }
  @override
  Future<StateFileInfo> describeState(File file) async {
    final base = await super.describeState(file);
    try {
      final first = (await file.readAsString()).split('\n').first;
      return StateFileInfo(
          savedAt: base.savedAt,
          emulatorVersion: first.startsWith('ver=') ? first.substring(4) : null);
    } catch (_) {
      return base;
    }
  }
  @override
  Future<Uint8List?> stateScreenshot(File file) async {
    final bytes = screenshots[p.basename(file.path)];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }
}

/// Emulator side of "fakeemu". Borrows Pcsx2Strategy's plumbing only for
/// construction; every identity field is overridden.
class FakeStateEmulator extends Pcsx2Strategy {
  FakeStateEmulator(super.ds,
      {this.id = 'fakeemu', this.loadsStates = true, this.version = '1.2.0'});
  final String id;
  final bool loadsStates;
  String? version;
  @override
  String get emulatorId => id;
  @override
  String get name => 'FakeEmu';
  @override
  List<String> get supportedSlugs => ['fakeplatform'];
  @override
  bool get supportsStateLoadOnLaunch => loadsStates;
  @override
  List<String> stateLoadArgs(String statePath) => ['--load', statePath];
  /// How many times [installedVersion] was asked.
  int versionCalls = 0;
  @override
  Future<String?> installedVersion() async {
    versionCalls++;
    return version;
  }
}

/// Content for a fakeemu state file: 200+ bytes, recording [version].
List<int> fakeState(String version, {int seed = 1}) =>
    [...'ver=$version\n'.codeUnits, ...List.filled(200, seed)];
