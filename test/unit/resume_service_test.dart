import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/resume_service.dart';
import 'package:freegosy/core/save/save_state_info.dart';
import 'package:freegosy/core/save/save_strategy.dart';
import 'package:freegosy/core/save/state_sync_capable.dart';
import 'package:freegosy/core/save/state_sync_record.dart';
import 'package:freegosy/core/save/state_sync_service.dart';
import 'package:freegosy/core/storage/app_preferences.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_romm_states_api.dart';
import '../helpers/fake_state_emulator.dart';

/// A strategy whose matcher accepts every name, so a test can isolate
/// ResumeService's own "is this a bare file name" check from the strategy's
/// own filtering (the real strategies also filter names, which would mask
/// a broken safety check).
class _PermissiveSaveStrategy extends SaveStrategy with StateSyncCapable {
  _PermissiveSaveStrategy(this.dir);
  final String dir;

  @override
  String get strategyId => 'fakeemu';
  @override
  Future<String?> getSaveDir(Game game, String romPath) async => null;
  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
          {DateTime? sessionStart, String syncMode = 'both'}) async =>
      [];
  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async => false;
  @override
  Future<String> stateDirectory(Game game, String romPath) async => dir;
  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async =>
      (_) => true;
}

/// A strategy whose describeState breaks the "must never throw" contract of
/// StateSyncCapable, to prove checkBeforeLaunch survives a misbehaving
/// strategy instead of throwing out of the resume path.
class _ThrowingDescribeStrategy extends FakeStateSaveStrategy {
  _ThrowingDescribeStrategy(super.dir);
  @override
  Future<StateFileInfo> describeState(File file) async => throw Exception('describeState boom');
}

void main() {
  late Directory tmp;
  late String statesDir;
  late AppPreferences prefs;
  late FakeRommStatesApi api;
  late DirectoryService ds;
  late FakeStateEmulator emu;
  late FakeStateSaveStrategy save;
  late Game game;
  late String romPath;
  late bool offline;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('resume_service');
    statesDir = p.join(tmp.path, 'states');
    SharedPreferences.setMockInitialValues({});
    prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    api = FakeRommStatesApi();
    ds = DirectoryService(prefs);
    emu = FakeStateEmulator(ds);
    save = FakeStateSaveStrategy(statesDir);
    game = Game(id: '42', name: 'Test Game', platformSlug: 'fakeplatform', fileSize: 0);
    romPath = p.join(tmp.path, 'game.rom');
    offline = false;
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  ResumeService build({
    List<EmulatorStrategy>? emulators,
    bool withApi = true,
    SaveStrategy? Function(Game game, {String? emulatorId})? resolveSaveStrategy,
  }) =>
      ResumeService(
        emulatorsFor: (slug) => slug == 'fakeplatform' ? (emulators ?? [emu]) : [],
        resolveSaveStrategy: resolveSaveStrategy ??
            (g, {emulatorId}) => emulatorId == emu.emulatorId ? save : null,
        prefs: prefs,
        api: withApi ? api : null,
        isOffline: () => offline,
      );

  Future<List<ResumeEntry>> lastOf(Stream<List<ResumeEntry>> s) async => (await s.toList()).last;

  File writeLocal(String name, String version, {DateTime? at, String? dir}) {
    final file = File(p.join(dir ?? statesDir, name));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(fakeState(version));
    if (at != null) file.setLastModifiedSync(at);
    return file;
  }

  Future<void> syncOn([String emulatorId = 'fakeemu']) =>
      prefs.setBool(StateSyncService.enabledKey(emulatorId), true);

  ResumeEntry entryFor(List<ResumeEntry> entries, String fileName) =>
      entries.firstWhere((e) => e.fileName == fileName,
          orElse: () => throw StateError('no entry for $fileName in $entries'));

  // ─── 1 ────────────────────────────────────────────────────────────────────
  test('local states, newest first, with slot, version and compat', () async {
    writeLocal('GAME.auto.st', '1.2.0', at: DateTime(2026, 1, 1, 21, 10));
    writeLocal('GAME.1.st', '1.2.0', at: DateTime(2026, 1, 1, 19, 0));
    final service = build();

    final emissions = await service.entriesFor(game, [romPath]).toList();

    expect(emissions.length, 1);
    final entries = emissions.single;
    expect(entries.map((e) => e.fileName).toList(), ['GAME.auto.st', 'GAME.1.st']);
    expect(entries[0].slot, const AutoStateSlot());
    expect(entries[1].slot, const NumberedStateSlot(1));
    expect(entries.every((e) => e.where == ResumeWhere.thisPc), isTrue);
    expect(entries.every((e) => e.compat == StateCompat.ok), isTrue);
    expect(entries.every((e) => e.emulatorVersion == '1.2.0'), isTrue);
    expect(entries.every((e) => e.emulatorName == 'FakeEmu'), isTrue);
    expect(api.calls, isEmpty);
  });

  // ─── 2 ────────────────────────────────────────────────────────────────────
  test('a version different from the installed one is a mismatch; unknown installed version is unknown', () async {
    writeLocal('GAME.1.st', '1.0.0');
    final service = build();

    var entries = await lastOf(service.entriesFor(game, [romPath]));
    expect(entryFor(entries, 'GAME.1.st').compat, StateCompat.mismatch);

    emu.version = null;
    entries = await lastOf(service.entriesFor(game, [romPath]));
    expect(entryFor(entries, 'GAME.1.st').compat, StateCompat.unknown);
  });

  // ─── 3 ────────────────────────────────────────────────────────────────────
  test('sync off: RomM is never asked', () async {
    writeLocal('GAME.auto.st', '1.2.0');
    final service = build();

    await lastOf(service.entriesFor(game, [romPath]));

    expect(api.calls, isEmpty);
  });

  // ─── 4 ────────────────────────────────────────────────────────────────────
  test('offline: RomM is never asked', () async {
    await syncOn();
    offline = true;
    writeLocal('GAME.auto.st', '1.2.0');
    final service = build();

    final emissions = await service.entriesFor(game, [romPath]).toList();

    expect(emissions.length, 1);
    expect(api.calls, isEmpty);
  });

  // ─── 5 ────────────────────────────────────────────────────────────────────
  test('sync on: local list first, then merged with RomM', () async {
    await syncOn();
    writeLocal('GAME.auto.st', '1.2.0');
    api.seed('42', 'GAME.auto.st', fakeState('1.2.0'));
    api.seed('42', 'GAME.2.st', fakeState('1.2.0'), emulator: 'fakeemu');
    final service = build();

    final emissions = await service.entriesFor(game, [romPath]).toList();

    expect(emissions.length, 2);
    expect(emissions[0].length, 1);
    expect(emissions[0].single.where, ResumeWhere.thisPc);

    expect(emissions[1].length, 2);
    final remoteOnly = entryFor(emissions[1], 'GAME.2.st');
    expect(remoteOnly.where, ResumeWhere.romm);
    expect(remoteOnly.emulatorVersion, isNull);
    expect(remoteOnly.compat, StateCompat.unknown);
    final both = entryFor(emissions[1], 'GAME.auto.st');
    expect(both.where, ResumeWhere.both);
  });

  test('every entry remembers the ROM it was identified with (multi-disc: its own disc)', () async {
    await syncOn();
    writeLocal('GAME.auto.st', '1.2.0');
    api.seed('42', 'GAME.auto.st', fakeState('1.2.0'));
    api.seed('42', 'GAME.2.st', fakeState('1.2.0'), emulator: 'fakeemu');
    final service = build();

    final emissions = await service.entriesFor(game, [romPath]).toList();

    expect(emissions.expand((list) => list).map((e) => e.romPath).toSet(), {romPath},
        reason: 'local, both and RomM-only entries all carry the ROM the list was built from');
  });

  test('a RomM-only state that was synced and then deleted locally is not listed (the pull never restores it)',
      () async {
    await syncOn();
    final state = api.seed('42', 'GAME.1.st', fakeState('1.2.0'));
    api.seed('42', 'GAME.2.st', fakeState('1.2.0')); // no record: never synced here
    await StateRecordStore(prefs).save('42', {
      'GAME.1.st':
          StateSyncRecord(rommStateId: state.id, lastSyncedHash: 'x', serverUpdatedAt: state.updatedAt),
    });
    final service = build();

    final entries = await lastOf(service.entriesFor(game, [romPath]));

    expect(entries.any((e) => e.fileName == 'GAME.1.st'), isFalse);
    expect(entryFor(entries, 'GAME.2.st').where, ResumeWhere.romm);
  });

  test("multi-disc: every disc's states are listed, each with its own disc; RomM is asked once", () async {
    final perDisc = FakeStateSaveStrategy(statesDir, perDisc: true);
    final disc1 = p.join(tmp.path, 'G', 'Disc 1.iso');
    final disc2 = p.join(tmp.path, 'G', 'Disc 2.iso');
    await syncOn();
    writeLocal('GAME-Disc 1.auto.st', '1.2.0');
    writeLocal('GAME-Disc 2.1.st', '1.2.0');
    api.seed('42', 'GAME-Disc 2.3.st', fakeState('1.2.0'), emulator: 'fakeemu');
    api.seed('42', 'GAME-Disc 1.2.st', fakeState('1.2.0'));
    api.seed('42', 'GAME-Disc 1.auto.st', fakeState('1.2.0'));
    final service = build(resolveSaveStrategy: (g, {emulatorId}) => perDisc);

    final emissions = await service.entriesFor(game, [disc1, disc2]).toList();

    expect({for (final e in emissions.first) e.fileName: e.romPath},
        {'GAME-Disc 1.auto.st': disc1, 'GAME-Disc 2.1.st': disc2});
    expect({for (final e in emissions.last) e.fileName: e.romPath}, {
      'GAME-Disc 1.auto.st': disc1,
      'GAME-Disc 2.1.st': disc2,
      'GAME-Disc 2.3.st': disc2,
      'GAME-Disc 1.2.st': disc1,
    });
    expect(entryFor(emissions.last, 'GAME-Disc 1.auto.st').where, ResumeWhere.both);
    expect(entryFor(emissions.last, 'GAME-Disc 2.3.st').slot, const NumberedStateSlot(3));
    expect(api.calls.where((c) => c == 'list').length, 1);

    final check = await service.checkBeforeLaunch(
        entryFor(emissions.last, 'GAME-Disc 2.1.st'), game, disc2) as ResumeReady;
    expect(check.path, p.join(statesDir, 'GAME-Disc 2.1.st'));
  });

  test('several ROM files of one emulator claiming the same states (cue/bin tracks): listed once, first path owns them',
      () async {
    // The plain fake matcher accepts GAME.*.st whatever the ROM file.
    await syncOn();
    writeLocal('GAME.auto.st', '1.2.0');
    api.seed('42', 'GAME.auto.st', fakeState('1.2.0'));
    api.seed('42', 'GAME.2.st', fakeState('1.2.0'), emulator: 'fakeemu');
    api.seed('42', 'GAME.3.st', fakeState('1.2.0'));
    final track1 = p.join(tmp.path, 'G', 'Track 01.bin');
    final track2 = p.join(tmp.path, 'G', 'Track 02.bin');
    final service = build();

    // Given out of order: ownership follows sorted path order, not argument order.
    final emissions = await service.entriesFor(game, [track2, track1]).toList();

    expect(emissions.first.map((e) => (e.fileName, e.romPath)).toList(), [('GAME.auto.st', track1)]);
    final last = emissions.last;
    expect(last.map((e) => e.fileName).toList()..sort(), ['GAME.2.st', 'GAME.3.st', 'GAME.auto.st']);
    expect(last.every((e) => e.romPath == track1), isTrue);
    expect(entryFor(last, 'GAME.auto.st').where, ResumeWhere.both);
  });

  test('a RomM state two different emulators both match, with no tag deciding, is left out', () async {
    final emu2 = FakeStateEmulator(ds, id: 'fakeemu2');
    final save2 = FakeStateSaveStrategy(p.join(tmp.path, 'states2'), id: 'fakeemu2');
    await syncOn('fakeemu');
    await syncOn('fakeemu2');
    api.seed('42', 'GAME.4.st', fakeState('1.2.0'));
    final service = build(
      emulators: [emu, emu2],
      resolveSaveStrategy: (g, {emulatorId}) => emulatorId == 'fakeemu2' ? save2 : save,
    );

    final entries =
        await lastOf(service.entriesFor(game, [p.join(tmp.path, 'd1.iso'), p.join(tmp.path, 'd2.iso')]));

    expect(entries.any((e) => e.fileName == 'GAME.4.st'), isFalse);
  });

  test('the installed version is asked once per emulator, however many discs', () async {
    final perDisc = FakeStateSaveStrategy(statesDir, perDisc: true);
    writeLocal('GAME-d1.auto.st', '1.2.0');
    writeLocal('GAME-d2.auto.st', '1.2.0');
    final service = build(resolveSaveStrategy: (g, {emulatorId}) => perDisc);

    final entries = await lastOf(service.entriesFor(
        game, [p.join(tmp.path, 'd1.iso'), p.join(tmp.path, 'd2.iso'), p.join(tmp.path, 'd3.iso')]));

    expect(entries.length, 2);
    expect(emu.versionCalls, 1);
  });

  test('no ROM paths: a single empty list', () async {
    writeLocal('GAME.auto.st', '1.2.0');
    expect(await build().entriesFor(game, const []).toList(), [<ResumeEntry>[]]);
  });

  // ─── 6 ────────────────────────────────────────────────────────────────────
  test('ownership: an unrecognised tag falls back to the name matcher', () async {
    await syncOn();
    api.seed('42', 'GAME.3.st', fakeState('1.2.0'), emulator: 'freegosy');
    final service = build();

    final entries = await lastOf(service.entriesFor(game, [romPath]));

    expect(entryFor(entries, 'GAME.3.st').emulatorId, 'fakeemu');
  });

  // ─── 7 ────────────────────────────────────────────────────────────────────
  test('ownership: two emulators matching the name → left out; tag decides', () async {
    final emu2 = FakeStateEmulator(ds, id: 'fakeemu2');
    final save2 = FakeStateSaveStrategy(p.join(tmp.path, 'states2'), id: 'fakeemu2');
    await syncOn('fakeemu');
    await syncOn('fakeemu2');
    api.seed('42', 'GAME.4.st', fakeState('1.2.0'));
    api.seed('42', 'GAME.5.st', fakeState('1.2.0'), emulator: 'FAKEEMU2');
    final service = build(
      emulators: [emu, emu2],
      resolveSaveStrategy: (g, {emulatorId}) {
        if (emulatorId == emu.emulatorId) return save;
        if (emulatorId == emu2.emulatorId) return save2;
        return null;
      },
    );

    final entries = await lastOf(service.entriesFor(game, [romPath]));

    expect(entries.any((e) => e.fileName == 'GAME.4.st'), isFalse);
    final entry5 = entryFor(entries, 'GAME.5.st');
    expect(entry5.emulatorId, 'fakeemu2');
  });

  // ─── 8 ────────────────────────────────────────────────────────────────────
  test('unsafe or non-matching server names are never listed', () async {
    await syncOn();

    // Non-matching names: rejected by the emulator's own file matcher.
    api.seed('42', 'GAME.1.st.bak', fakeState('1.2.0'));
    api.seed('42', 'other.st', fakeState('1.2.0'));
    final matcherService = build();
    final matcherEntries = await lastOf(matcherService.entriesFor(game, [romPath]));
    expect(matcherEntries, isEmpty);

    // Unsafe names: rejected outright, even against a strategy that matches
    // every name — a listed name later becomes a local path.
    final unsafeApi = FakeRommStatesApi();
    unsafeApi.seed('42', '../GAME.1.st', fakeState('1.2.0'));
    unsafeApi.seed('42', 'a/GAME.1.st', fakeState('1.2.0'));
    final permissive = _PermissiveSaveStrategy(statesDir);
    final unsafeService = ResumeService(
      emulatorsFor: (slug) => slug == 'fakeplatform' ? [emu] : [],
      resolveSaveStrategy: (g, {emulatorId}) => permissive,
      prefs: prefs,
      api: unsafeApi,
      isOffline: () => offline,
    );
    final unsafeEntries = await lastOf(unsafeService.entriesFor(game, [romPath]));
    expect(unsafeEntries, isEmpty);
  });

  // ─── 9 ────────────────────────────────────────────────────────────────────
  test("newerOnRomm when the record's updatedAt differs; version then unknown", () async {
    await syncOn();
    writeLocal('GAME.1.st', '1.2.0');
    final state = api.seed('42', 'GAME.1.st', fakeState('1.2.0'));
    await StateRecordStore(prefs).save('42', {
      'GAME.1.st': StateSyncRecord(rommStateId: state.id, lastSyncedHash: 'x', serverUpdatedAt: 'old'),
    });
    final service = build();

    var entries = await lastOf(service.entriesFor(game, [romPath]));
    var entry = entryFor(entries, 'GAME.1.st');
    expect(entry.newerOnRomm, isTrue);
    expect(entry.emulatorVersion, isNull);
    expect(entry.compat, StateCompat.unknown);
    expect(entry.remoteUpdatedAt, state.updatedAt);

    await StateRecordStore(prefs).save('42', {
      'GAME.1.st':
          StateSyncRecord(rommStateId: state.id, lastSyncedHash: 'x', serverUpdatedAt: state.updatedAt),
    });
    entries = await lastOf(service.entriesFor(game, [romPath]));
    entry = entryFor(entries, 'GAME.1.st');
    expect(entry.newerOnRomm, isFalse);
    expect(entry.emulatorVersion, '1.2.0');
  });

  // ─── 10 ───────────────────────────────────────────────────────────────────
  test('emulators that cannot load states on launch take no part', () async {
    final noLoad = FakeStateEmulator(ds, loadsStates: false);
    writeLocal('GAME.auto.st', '1.2.0');
    final service = build(emulators: [noLoad]);

    final emissions = await service.entriesFor(game, [romPath]).toList();

    expect(emissions, [<ResumeEntry>[]]);
  });

  // ─── 11 ───────────────────────────────────────────────────────────────────
  test('missing states folder or unidentifiable game: empty, no throw', () async {
    final missingDirSave = FakeStateSaveStrategy(p.join(tmp.path, 'does_not_exist'));
    var service = build(resolveSaveStrategy: (g, {emulatorId}) => missingDirSave);
    var entries = await lastOf(service.entriesFor(game, [romPath]));
    expect(entries, isEmpty);

    save.identifiable = false;
    service = build();
    entries = await lastOf(service.entriesFor(game, [romPath]));
    expect(entries, isEmpty);
  });

  // ─── 12 ───────────────────────────────────────────────────────────────────
  test('listing failure keeps the local list', () async {
    await syncOn();
    writeLocal('GAME.auto.st', '1.2.0');
    api.failList = true;
    final service = build();

    final emissions = await service.entriesFor(game, [romPath]).toList();

    expect(emissions.length, 1);
    expect(emissions.single.length, 1);
  });

  // ─── 13 ───────────────────────────────────────────────────────────────────
  test('tiny local files are ignored', () async {
    final file = File(p.join(statesDir, 'GAME.1.st'));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(10, 1));
    final service = build();

    final entries = await lastOf(service.entriesFor(game, [romPath]));

    expect(entries, isEmpty);
  });

  // ─── 14 ───────────────────────────────────────────────────────────────────
  test('no participating emulator → a single empty list', () async {
    final other = Game(id: '99', name: 'Other Game', platformSlug: 'other-platform', fileSize: 0);
    final service = build();

    final emissions = await service.entriesFor(other, [romPath]).toList();

    expect(emissions, [<ResumeEntry>[]]);
  });

  // ─── 15 ───────────────────────────────────────────────────────────────────
  test('checkBeforeLaunch: local file present → ready, no prompt when the list already showed the version',
      () async {
    writeLocal('GAME.1.st', '1.0.0');
    final service = build();
    final entries = await lastOf(service.entriesFor(game, [romPath]));
    final entry = entryFor(entries, 'GAME.1.st');
    expect(entry.compat, StateCompat.mismatch);

    final check = await service.checkBeforeLaunch(entry, game, romPath);

    expect(check, isA<ResumeReady>());
    expect((check as ResumeReady).prompt, isNull);
  });

  // ─── 16 ───────────────────────────────────────────────────────────────────
  test('checkBeforeLaunch: romm-only entry now on disk with a mismatched version → prompt', () async {
    await syncOn();
    api.seed('42', 'GAME.2.st', fakeState('1.2.0'));
    final service = build();
    final entries = await lastOf(service.entriesFor(game, [romPath]));
    final entry = entryFor(entries, 'GAME.2.st');
    expect(entry.where, ResumeWhere.romm);

    writeLocal('GAME.2.st', '1.0.0'); // simulates the pre-launch pull

    final check = await service.checkBeforeLaunch(entry, game, romPath);

    expect(check, isA<ResumeReady>());
    final ready = check as ResumeReady;
    expect(ready.prompt, (stateVersion: '1.0.0', installed: '1.2.0'));
  });

  // ─── 17 ───────────────────────────────────────────────────────────────────
  test('checkBeforeLaunch: file missing after the pull → ResumeMissing', () async {
    await syncOn();
    api.seed('42', 'GAME.2.st', fakeState('1.2.0'));
    final service = build();
    final entries = await lastOf(service.entriesFor(game, [romPath]));
    final entry = entryFor(entries, 'GAME.2.st');

    final check = await service.checkBeforeLaunch(entry, game, romPath);

    expect(check, isA<ResumeMissing>());
  });

  // ─── 18 ───────────────────────────────────────────────────────────────────
  test('checkBeforeLaunch: local copy loads even if the pull did nothing (busy)', () async {
    final file = writeLocal('GAME.auto.st', '1.2.0');
    final service = build();
    final entries = await lastOf(service.entriesFor(game, [romPath]));
    final entry = entryFor(entries, 'GAME.auto.st');

    final check = await service.checkBeforeLaunch(entry, game, romPath);

    expect(check, isA<ResumeReady>());
    final ready = check as ResumeReady;
    expect(ready.stale, isFalse);
    expect(ready.path, file.path);
  });

  // ─── 19 ───────────────────────────────────────────────────────────────────
  test('checkBeforeLaunch: newerOnRomm is stale unless the pull downloaded it or it was a conflict', () async {
    await syncOn();
    writeLocal('GAME.1.st', '1.2.0');
    final state = api.seed('42', 'GAME.1.st', fakeState('1.2.0'));
    await StateRecordStore(prefs).save('42', {
      'GAME.1.st': StateSyncRecord(rommStateId: state.id, lastSyncedHash: 'x', serverUpdatedAt: 'old'),
    });
    final service = build();
    final entries = await lastOf(service.entriesFor(game, [romPath]));
    final entry = entryFor(entries, 'GAME.1.st');
    expect(entry.newerOnRomm, isTrue);

    // No pull ran at all (offline, sync unavailable, a throwing pull).
    var check = await service.checkBeforeLaunch(entry, game, romPath) as ResumeReady;
    expect(check.stale, isTrue);

    // A pull ran but did not bring this file down.
    check = await service.checkBeforeLaunch(entry, game, romPath,
        pulled: {'GAME.2.st'}, conflicted: const {}) as ResumeReady;
    expect(check.stale, isTrue);

    // The pull downloaded it.
    check = await service.checkBeforeLaunch(entry, game, romPath,
        pulled: {'GAME.1.st'}, conflicted: const {}) as ResumeReady;
    expect(check.stale, isFalse);

    // RomM had only re-stamped it: the pull confirmed the local copy is the
    // current one (handleLaunch passes the pull's currentFiles as pulled).
    final restamp = const StateSyncResult(upToDateFiles: {'GAME.1.st'});
    check = await service.checkBeforeLaunch(entry, game, romPath,
        pulled: restamp.currentFiles,
        conflicted: const {}) as ResumeReady;
    expect(check.stale, isFalse);

    // It was a conflict: whichever copy is on disk is the user's own choice.
    check = await service.checkBeforeLaunch(entry, game, romPath,
        pulled: const {}, conflicted: {'GAME.1.st'}) as ResumeReady;
    expect(check.stale, isFalse);
  });

  test('checkBeforeLaunch: not newer on RomM is never stale', () async {
    writeLocal('GAME.1.st', '1.2.0');
    final service = build();
    final entry = entryFor(await lastOf(service.entriesFor(game, [romPath])), 'GAME.1.st');

    final check = await service.checkBeforeLaunch(entry, game, romPath, pulled: const {}) as ResumeReady;

    expect(check.stale, isFalse);
  });

  // ─── 20 ───────────────────────────────────────────────────────────────────
  test('checkBeforeLaunch: equal versions or unknown → no prompt', () async {
    writeLocal('GAME.1.st', '1.2.0'); // equal to the installed version
    var service = build();
    var entries = await lastOf(service.entriesFor(game, [romPath]));
    var entry = entryFor(entries, 'GAME.1.st');
    var check = await service.checkBeforeLaunch(entry, game, romPath) as ResumeReady;
    expect(check.prompt, isNull);

    emu.version = null; // unknown installed version
    entries = await lastOf(service.entriesFor(game, [romPath]));
    entry = entryFor(entries, 'GAME.1.st');
    check = await service.checkBeforeLaunch(entry, game, romPath) as ResumeReady;
    expect(check.prompt, isNull);
  });

  test('checkBeforeLaunch: listed without a mismatch, emulator updated since → prompt', () async {
    writeLocal('GAME.1.st', '1.2.0');
    final service = build();
    var entry = entryFor(await lastOf(service.entriesFor(game, [romPath])), 'GAME.1.st');
    expect(entry.compat, StateCompat.ok);

    emu.version = '1.3.0'; // the emulator was updated after the list was built
    var check = await service.checkBeforeLaunch(entry, game, romPath) as ResumeReady;
    expect(check.prompt, (stateVersion: '1.2.0', installed: '1.3.0'));

    emu.version = null; // listed with an unknown installed version
    entry = entryFor(await lastOf(service.entriesFor(game, [romPath])), 'GAME.1.st');
    expect(entry.compat, StateCompat.unknown);
    emu.version = '1.3.0';
    check = await service.checkBeforeLaunch(entry, game, romPath) as ResumeReady;
    expect(check.prompt, (stateVersion: '1.2.0', installed: '1.3.0'));
  });

  // ─── 20b ──────────────────────────────────────────────────────────────────
  test('checkBeforeLaunch: a throwing describeState yields ready with no prompt, not a throw', () async {
    final file = writeLocal('GAME.1.st', '1.0.0');
    final entries = await lastOf(build().entriesFor(game, [romPath]));
    final entry = entryFor(entries, 'GAME.1.st');

    final throwing = _ThrowingDescribeStrategy(statesDir);
    final service = build(resolveSaveStrategy: (g, {emulatorId}) => throwing);

    final check = await service.checkBeforeLaunch(entry, game, romPath);

    expect(check, isA<ResumeReady>());
    final ready = check as ResumeReady;
    expect(ready.prompt, isNull);
    expect(ready.path, file.path);
  });

  // ─── 21 ───────────────────────────────────────────────────────────────────
  test('thumbnailFor: local via the strategy, remote via the API, cached; failures → null', () async {
    await syncOn();
    save.screenshots['GAME.auto.st'] = [1, 2];
    writeLocal('GAME.auto.st', '1.2.0');
    api.seed('42', 'GAME.2.st', fakeState('1.2.0'), screenshot: [3]);
    final service = build();
    final entries = await lastOf(service.entriesFor(game, [romPath]));

    final local = entryFor(entries, 'GAME.auto.st');
    expect(await service.thumbnailFor(local), [1, 2]);

    final remote = entryFor(entries, 'GAME.2.st');
    expect(await service.thumbnailFor(remote), [3]);
    final shotCallsAfterFirst = api.calls.where((c) => c.startsWith('SHOT')).length;
    expect(await service.thumbnailFor(remote), [3]);
    expect(api.calls.where((c) => c.startsWith('SHOT')).length, shotCallsAfterFirst);

    api.failScreenshots = true;
    api.seed('42', 'GAME.6.st', fakeState('1.2.0'), screenshot: [9]);
    final entries2 = await lastOf(service.entriesFor(game, [romPath]));
    final failing = entryFor(entries2, 'GAME.6.st');
    expect(await service.thumbnailFor(failing), isNull);
  });
  test('thumbnailFor: a failed download is not cached; the next call retries', () async {
    await syncOn();
    api.seed('42', 'GAME.2.st', fakeState('1.2.0'), screenshot: [3]);
    final service = build();
    final remote = entryFor(await lastOf(service.entriesFor(game, [romPath])), 'GAME.2.st');

    api.failScreenshots = true;
    expect(await service.thumbnailFor(remote), isNull);
    api.failScreenshots = false;
    expect(await service.thumbnailFor(remote), [3]);
  });

  test('thumbnailFor: the cache keeps at most 32 thumbnails', () async {
    final service = build(withApi: false);
    for (var i = 0; i < 33; i++) {
      await service.thumbnailFor(ResumeEntry(
        emulatorId: 'fakeemu',
        emulatorName: 'FakeEmu',
        fileName: 'GAME.$i.st',
        slot: NumberedStateSlot(i),
        savedAt: DateTime(2026, 1, 1),
        where: ResumeWhere.romm,
      ));
    }
    expect(service.thumbnailCacheSize, 32);
  });
  group('resumeMissingMessage', () {
    ResumeEntry entry(ResumeWhere where, {bool newerOnRomm = false}) => ResumeEntry(
          emulatorId: 'fakeemu',
          emulatorName: 'FakeEmu',
          fileName: 'GAME.1.st',
          slot: const NumberedStateSlot(1),
          savedAt: DateTime(2026, 1, 1),
          where: where,
          newerOnRomm: newerOnRomm,
        );

    test('RomM-only or newer on RomM: it could not be fetched from RomM', () {
      expect(resumeMissingMessage(entry(ResumeWhere.romm), serviceAvailable: true),
          "Couldn't get Slot 1 from RomM. Nothing was started.");
      expect(resumeMissingMessage(entry(ResumeWhere.both, newerOnRomm: true), serviceAvailable: true),
          "Couldn't get Slot 1 from RomM. Nothing was started.");
    });

    test('a local copy that is gone: not found on this PC', () {
      expect(resumeMissingMessage(entry(ResumeWhere.thisPc), serviceAvailable: true),
          "Couldn't find Slot 1 on this PC. Nothing was started.");
      expect(resumeMissingMessage(entry(ResumeWhere.both), serviceAvailable: true),
          "Couldn't find Slot 1 on this PC. Nothing was started.");
    });

    test('no resume service: resume is not available', () {
      expect(resumeMissingMessage(entry(ResumeWhere.romm), serviceAvailable: false),
          "Resume isn't available right now. Nothing was started.");
    });
  });
}
