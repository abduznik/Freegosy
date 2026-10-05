import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/catalog/play_choice.dart';
import 'package:freegosy/core/save/catalog/play_view.dart';
import 'package:freegosy/core/save/catalog/save_catalog.dart';
import 'package:freegosy/core/save/catalog/save_entry.dart';
import 'package:freegosy/core/save/catalog/save_maker.dart';
import 'package:freegosy/core/save/resume_service.dart';
import 'package:freegosy/core/save/save_state_info.dart';

void main() {
  const rearmed = SaveMaker('retroarch', coreId: 'pcsx_rearmed');
  const duck = SaveMaker('duckstation'); // its PS1 cards convert for RetroArch's cores
  const ares = SaveMaker('ares'); // no PS1 save format: others' saves can't be used by it
  final mon = DateTime(2026, 9, 28), tue = DateTime(2026, 9, 29), wed = DateTime(2026, 9, 30);

  SaveEntry local(SaveMaker m, DateTime t) => SaveEntry(source: SaveSource.local, fileName: 'l-${m.tag}', savedAt: t, maker: m, tag: m.tag);
  SaveEntry romm(String name, SaveMaker? m, DateTime t, {String slot = 'freegosy'}) =>
      SaveEntry(source: SaveSource.romm, fileName: name, savedAt: t, maker: m, tag: m?.tag ?? 'freegosy', slot: slot);
  RommSaveGroup group(List<SaveEntry> versions) =>
      RommSaveGroup(slot: versions.first.slot ?? '', tag: versions.first.tag ?? '', newest: versions.first, older: versions.sublist(1));
  ResumeEntry state(String emulator, DateTime t) => ResumeEntry(
      emulatorId: emulator, emulatorName: emulator, fileName: 's', slot: const NumberedStateSlot(1), savedAt: t, where: ResumeWhere.thisPc);

  PlayView view(SaveCatalog c, {SaveMaker? picked, bool showAll = false, List<ResumeEntry> states = const []}) => buildPlayView(
      catalog: c, states: states, platformSlug: 'psx', picked: picked, platformDefault: duck,
      installed: const {'retroarch', 'ares', 'duckstation'}, showAll: showAll);

  // A backup goes back only into the emulator it was made for, so RetroArch
  // can't use DuckStation's.
  final catalog = SaveCatalog(
    thisPc: [local(rearmed, tue)],
    backups: [SaveEntry(source: SaveSource.backup, fileName: 'd.zip', savedAt: wed, maker: duck, tag: duck.tag)],
    romm: [
      group([romm('a.mcd', duck, mon)]),
    ],
    rommOffline: false,
  );

  test('with an emulator picked, saves it can\'t use are hidden and counted', () {
    final v = view(catalog, picked: rearmed);
    expect(v.hidden, 1);
    expect(v.saveRows.map((r) => r.entry.fileName), ['l-pcsx_rearmed', 'a.mcd']);
  });

  test('Show all shows them again, unusable', () {
    final v = view(catalog, picked: rearmed, showAll: true);
    expect(v.hidden, 0);
    expect(v.saveRows.firstWhere((r) => r.entry.fileName == 'd.zip').fit.usable, isFalse);
  });

  test('with Any nothing is hidden', () {
    expect(view(catalog).hidden, 0);
  });

  test('a group whose newest version is hidden shows its newest usable one', () {
    // ares picked: the newest version (DuckStation's) can't be used, its own
    // older one can.
    final c = SaveCatalog(thisPc: const [], backups: const [], rommOffline: false, romm: [
      group([romm('new.srm', duck, wed, slot: 's'), romm('old.mcd', ares, mon, slot: 's')]),
    ]);
    final v = view(c, picked: ares);
    expect(v.romm.single.newest.entry.fileName, 'old.mcd');
    expect(v.romm.single.older, isEmpty);
    expect(v.hidden, 1);
  });

  test('states are filtered by the picked emulator', () {
    final v = view(catalog, picked: rearmed, states: [state('retroarch', mon), state('ares', mon)]);
    expect(v.states.map((s) => s.emulatorId), ['retroarch']);
  });

  test('the newest usable save is preselected; a newer state wins', () {
    expect((view(catalog, picked: rearmed).preselected as SavePlay).entry.fileName, 'l-pcsx_rearmed');
    expect(view(catalog, picked: rearmed, states: [state('retroarch', wed)]).preselected, isA<StatePlay>());
  });

  test('an older RomM save than the target\'s local save asks first; the local save does not', () {
    // The local save is on RomM (synced as RomM's save 7): only its time is in question.
    final onRomm = SaveCatalog(
      thisPc: [SaveEntry(source: SaveSource.local, fileName: 'l', savedAt: tue, maker: rearmed, tag: rearmed.tag, sameAsRommId: '7')],
      backups: const [],
      romm: [
        group([romm('a.mcd', duck, mon)]),
        group([SaveEntry(source: SaveSource.romm, fileName: 'mine', savedAt: tue, maker: rearmed, tag: rearmed.tag,
            slot: 'other', rommSave: {'id': 7})]),
      ],
      rommOffline: false,
    );
    final v = view(onRomm, picked: rearmed);
    final older = v.saveRows.firstWhere((r) => r.entry.fileName == 'a.mcd');
    expect(v.promptFor(older.item), PlayPrompt.olderSave);
    expect(v.promptFor(v.thisPc.single.item), isNull);
    expect(v.newestLocalFor(rearmed), tue);
  });

  test('a backup is never the newest save: not preselected, and not counted for states', () {
    final c = SaveCatalog(
      thisPc: [local(rearmed, mon)],
      backups: [SaveEntry(source: SaveSource.backup, fileName: 'b.zip', savedAt: wed, maker: rearmed, tag: 'retroarch')],
      romm: const [],
      rommOffline: false,
    );
    final v = view(c, picked: rearmed, states: [state('retroarch', tue)]);
    expect(v.newestSave, mon);
    expect(v.preselected, isA<StatePlay>(), reason: 'the state is newer than the save itself');
  });

  test('RomM\'s copy of the local save is not preselected over it; a newer upload is', () {
    final mine = SaveEntry(source: SaveSource.local, fileName: 'l', savedAt: tue, maker: rearmed, tag: 'pcsx_rearmed', sameAsRommId: '41');
    SaveEntry copy(String id, DateTime t) => SaveEntry(source: SaveSource.romm, fileName: 'r$id', savedAt: t, maker: rearmed,
        tag: 'pcsx_rearmed', slot: 'freegosy', rommSave: {'id': int.parse(id)});
    PlayItem? pre(List<SaveEntry> versions) =>
        view(SaveCatalog(thisPc: [mine], backups: const [], romm: [group(versions)], rommOffline: false), picked: rearmed).preselected;

    expect((pre([copy('41', wed)]) as SavePlay).entry.source, SaveSource.local);
    expect((pre([copy('42', wed), copy('41', tue)]) as SavePlay).entry.fileName, 'r42');
  });

  test('RomM\'s save with the content_hash of the local save is its copy: marked, not preselected over it', () {
    final mine = SaveEntry(source: SaveSource.local, fileName: 'l', savedAt: tue, maker: rearmed, tag: 'pcsx_rearmed', contentHashes: const {'h1'});
    SaveEntry remote(String hash, DateTime t) => SaveEntry(source: SaveSource.romm, fileName: 'r-$hash', savedAt: t, maker: rearmed,
        tag: 'pcsx_rearmed', slot: 'freegosy', rommSave: {'id': hash.hashCode, 'content_hash': hash});
    PlayView v(List<SaveEntry> versions) =>
        view(SaveCatalog(thisPc: [mine], backups: const [], romm: [group(versions)], rommOffline: false), picked: rearmed);

    final same = v([remote('h1', wed)]);
    expect((same.preselected as SavePlay).entry.source, SaveSource.local);
    expect(same.romm.single.newest.sameAsLocal, isTrue);

    final other = v([remote('h2', wed)]);
    expect((other.preselected as SavePlay).entry.fileName, 'r-h2');
    expect(other.romm.single.newest.sameAsLocal, isFalse);
  });

  test('with Show all, an unusable local save doesn\'t hide RomM\'s copy of it', () {
    // RetroArch's PCSX-ReARMed picked; the local save is another core's.
    const otherCore = SaveMaker('retroarch', coreId: 'swanstation');
    final theirs = SaveEntry(source: SaveSource.local, fileName: 'l', savedAt: tue, maker: otherCore, tag: 'swanstation',
        contentHashes: const {'h1'}, sameAsRommId: '9');
    final copy = SaveEntry(source: SaveSource.romm, fileName: 'r', savedAt: wed, maker: otherCore, tag: 'swanstation',
        slot: 'freegosy', rommSave: {'id': 9, 'content_hash': 'h1'});
    final v = view(SaveCatalog(thisPc: [theirs], backups: const [], romm: [group([copy])], rommOffline: false),
        picked: rearmed, showAll: true);
    expect(v.thisPc.single.fit.usable, isFalse);
    expect((v.preselected as SavePlay).entry.fileName, 'r');
  });

  test('a RomM copy uploaded in "both" mode (save and states) is recognised too', () {
    final mine = SaveEntry(source: SaveSource.local, fileName: 'l', savedAt: tue, maker: rearmed, tag: 'pcsx_rearmed',
        contentHashes: const {'saves-only', 'with-states'});
    final copy = SaveEntry(source: SaveSource.romm, fileName: 'r', savedAt: wed, maker: rearmed, tag: 'pcsx_rearmed',
        slot: 'freegosy', rommSave: {'id': 3, 'content_hash': 'with-states'});
    final v = view(SaveCatalog(thisPc: [mine], backups: const [], romm: [group([copy])], rommOffline: false), picked: rearmed);
    expect(v.romm.single.newest.sameAsLocal, isTrue);
  });

  test('a save on this PC that isn\'t on RomM is never replaced without asking, even by a newer one', () {
    final mine = SaveEntry(source: SaveSource.local, fileName: 'l', savedAt: mon, maker: rearmed, tag: 'pcsx_rearmed',
        contentHashes: const {'mine'});
    SaveEntry remote(String hash, DateTime t) => SaveEntry(source: SaveSource.romm, fileName: 'r-$hash', savedAt: t,
        maker: rearmed, tag: 'pcsx_rearmed', slot: 'freegosy', rommSave: {'id': hash.hashCode, 'content_hash': hash});
    PlayView v(List<SaveEntry> versions) =>
        view(SaveCatalog(thisPc: [mine], backups: const [], romm: [group(versions)], rommOffline: false), picked: rearmed);

    final notUploaded = v([remote('other', wed)]);
    expect(notUploaded.promptFor(notUploaded.romm.single.newest.item), PlayPrompt.notOnRomm);
    expect(notUploaded.isOnRomm(mine), isFalse);

    // On RomM (an older version of it): a newer RomM save replaces it as before, no question.
    final uploaded = v([remote('other', wed), remote('mine', mon)]);
    expect(uploaded.isOnRomm(mine), isTrue);
    expect(uploaded.promptFor(uploaded.romm.single.newest.item), isNull);
  });

  test('a state older than the newest save asks first', () {
    final v = view(catalog, picked: rearmed, states: [state('retroarch', mon)]);
    expect(v.promptFor(StatePlay(v.states.single)), PlayPrompt.olderState);
  });

  test('a save on a shared card is not preselected over a usable RomM save, whatever its time', () {
    // Its time is the card's, which any game on the card changes.
    final shared = SaveEntry(
        source: SaveSource.local, fileName: 'card', savedAt: wed, maker: rearmed, tag: rearmed.tag, sharedFile: true);
    final withRomm = SaveCatalog(
        thisPc: [shared], backups: const [], romm: [group([romm('r.srm', rearmed, tue)])], rommOffline: false);
    final alone = SaveCatalog(thisPc: [shared], backups: const [], romm: const [], rommOffline: false);

    expect((view(withRomm, picked: rearmed).preselected as SavePlay).entry.fileName, 'r.srm');
    expect((view(alone, picked: rearmed).preselected as SavePlay).entry.fileName, 'card');
  });

  test('a save on a shared card that is on RomM counts as its RomM copy time', () {
    final shared = SaveEntry(source: SaveSource.local, fileName: 'card', savedAt: wed, maker: rearmed, tag: rearmed.tag,
        sharedFile: true, sameAsRommId: '41');
    SaveEntry copy(String id, DateTime t) => SaveEntry(source: SaveSource.romm, fileName: 'r$id', savedAt: t, maker: rearmed,
        tag: rearmed.tag, slot: 'freegosy', rommSave: {'id': int.parse(id)});
    PlayItem? pre(List<SaveEntry> versions) =>
        view(SaveCatalog(thisPc: [shared], backups: const [], romm: [group(versions)], rommOffline: false), picked: rearmed)
            .preselected;

    expect((pre([copy('41', mon)]) as SavePlay).entry.fileName, 'card');
    expect((pre([copy('42', tue), copy('41', mon)]) as SavePlay).entry.fileName, 'r42');
  });

  test('a state newer than the save is not called older because RomM got the save later', () {
    // RomM's copy is dated by its upload, after the session.
    final mine = SaveEntry(
        source: SaveSource.local, fileName: 'l', savedAt: tue, maker: rearmed, tag: rearmed.tag, contentHashes: const {'h'});
    final copy = SaveEntry(source: SaveSource.romm, fileName: 'r', savedAt: wed, maker: rearmed, tag: rearmed.tag,
        slot: 'freegosy', rommSave: const {'id': 1, 'content_hash': 'h'});
    final s = state('retroarch', tue.add(const Duration(hours: 23)));
    final v = view(SaveCatalog(thisPc: [mine], backups: const [], romm: [group([copy])], rommOffline: false),
        picked: rearmed, states: [s]);

    expect(v.promptFor(StatePlay(s)), isNull);
  });

  test('a save this PC uploaded is on RomM even after RomM pruned that upload', () {
    // Synced as RomM's save 41, which autocleanup has since removed.
    final mine = SaveEntry(source: SaveSource.local, fileName: 'l', savedAt: mon, maker: rearmed, tag: rearmed.tag,
        sameAsRommId: '41');
    final newer = SaveEntry(source: SaveSource.romm, fileName: 'r', savedAt: wed, maker: rearmed, tag: rearmed.tag,
        slot: 'freegosy', rommSave: const {'id': 46});
    final v = view(SaveCatalog(thisPc: [mine], backups: const [], romm: [group([newer])], rommOffline: false),
        picked: rearmed);

    expect(v.promptFor(v.romm.single.newest.item), isNull);
  });

  test('a shared card with nothing of this game on it is no save to ask about', () {
    final card = SaveEntry(source: SaveSource.local, fileName: 'Mcd001.ps2', savedAt: mon, maker: rearmed,
        tag: rearmed.tag, sharedFile: true);
    final remote = SaveEntry(source: SaveSource.romm, fileName: 'r', savedAt: wed, maker: rearmed, tag: rearmed.tag,
        slot: 'freegosy', rommSave: const {'id': 46, 'content_hash': 'x'});
    final v = view(SaveCatalog(thisPc: [card], backups: const [], romm: [group([remote])], rommOffline: false),
        picked: rearmed);

    expect(v.promptFor(v.romm.single.newest.item), isNull);
  });
}
