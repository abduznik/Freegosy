import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/input/gamepad_service.dart';
import 'package:freegosy/core/input/input_action_bus.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/catalog/play_request.dart';
import 'package:freegosy/core/save/catalog/save_catalog.dart';
import 'package:freegosy/core/save/catalog/save_entry.dart';
import 'package:freegosy/core/save/catalog/save_maker.dart';
import 'package:freegosy/core/save/resume_service.dart';
import 'package:freegosy/core/save/save_state_info.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:freegosy/providers/resume_provider.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:freegosy/providers/save_catalog_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/ui/screens/play_screen.dart';
import 'package:freegosy/ui/widgets/save_list/save_waiting.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _game = Game(id: '7', name: 'Mario Kart 64', fsName: 'mk', platformSlug: 'psx', fileSize: 0);
const _target = SaveMaker('retroarch', coreId: 'mednafen_psx_hw');
const _other = SaveMaker('duckstation');

// Labels say "today", so the dates follow the day the test runs.
final _now = DateTime.now();
DateTime _day(int daysAgo, int h, int m) => DateTime(_now.year, _now.month, _now.day - daysAgo, h, m);

SaveEntry _local(DateTime t) => SaveEntry(source: SaveSource.local, fileName: 'mk.eeprom', savedAt: t, maker: _target, tag: 'mednafen_psx_hw');
SaveEntry _romm(String name, SaveMaker? m, DateTime t) =>
    SaveEntry(source: SaveSource.romm, fileName: name, savedAt: t, maker: m, tag: m?.tag ?? 'freegosy', slot: name);
RommSaveGroup _g(SaveEntry e) => RommSaveGroup(slot: e.slot!, tag: e.tag!, newest: e, older: const []);

void main() {
  late SharedPreferences prefs;
  late List<PlayRequest> played;
  late List<ResumeEntry> resumed;
  // What onPlay answers: whether the emulator started.
  var starts = true;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    played = [];
    resumed = [];
    starts = true;
  });

  Future<void> open(WidgetTester tester,
      {String? remembered, SaveCatalog? catalog, List<ResumeEntry> states = const [], int? initialTab, Stream<List<ResumeEntry>>? statesLater}) async {
    final appPrefs = SharedPreferencesAppPreferences(prefs);
    final registry = StrategyRegistry(DirectoryService(appPrefs), appPrefs);
    if (remembered != null) await registry.setGameEmulatorPreference(_game.id, remembered);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        strategyRegistryProvider.overrideWith((ref) async => registry),
        emulatorStatusProvider.overrideWith((ref) async => {'retroarch': true, 'duckstation': true}),
        saveCatalogProvider.overrideWith((ref, key) async =>
            catalog ?? const SaveCatalog(thisPc: [], backups: [], romm: [], rommOffline: false)),
        resumeEntriesProvider.overrideWith((ref, key) => statesLater ?? Stream.value(states)),
        resumeServiceProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PlayScreen(
                  game: _game,
                  coverUrl: '',
                  initialTab: initialTab,
                  onPlay: (r) async {
                    played.add(r);
                    return starts;
                  },
                  onResume: (e) async => resumed.add(e),
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // RetroArch (Beetle PSX HW) remembered: DuckStation's RomM card converts;
  // DuckStation's backup can't be used by RetroArch (a backup goes back only
  // into its own emulator).
  final catalog = SaveCatalog(
    thisPc: [_local(_day(0, 9, 56))],
    backups: [SaveEntry(source: SaveSource.backup, fileName: 'ra-backup.zip', savedAt: _day(4, 12, 0), maker: _other, tag: _other.tag)],
    romm: [_g(_romm('mk.srm', _other, _day(3, 18, 40)))],
    rommOffline: false,
  );

  testWidgets('opens on the remembered emulator, with saves it can\'t use hidden and the newest preselected',
      (tester) async {
    await open(tester, remembered: 'retroarch', catalog: catalog);
    expect(find.text('remembered for this game'), findsOneWidget);
    expect(find.text('1 save hidden'), findsOneWidget);
    expect(find.byKey(const ValueKey('fold-backups')), findsNothing);
    expect(find.text('▶ Play'), findsOneWidget);
    expect(find.textContaining('local save, today 09:56'), findsOneWidget);
  });

  testWidgets('A on Play starts the preselected save in its emulator', (tester) async {
    await open(tester, remembered: 'retroarch', catalog: catalog);
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();
    expect(played.single.emulator, _target);
    expect(played.single.save, isNull, reason: 'the local save of the emulator itself: nothing to put in place');
    expect(played.single.remember, isTrue);
    expect(find.byType(PlayScreen), findsNothing, reason: 'the play screen closes once the game starts');
  });

  testWidgets('an older RomM save asks first; Cancel starts nothing, Replace and play does', (tester) async {
    await open(tester, remembered: 'retroarch', catalog: catalog);
    await tester.ensureVisible(find.text('mk.srm'));
    await tester.tap(find.text('mk.srm'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();
    // The save on this PC was never uploaded: that question comes first.
    expect(find.text("Your save on this PC isn't on RomM"), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(played, isEmpty);

    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace and play'));
    await tester.pumpAndSettle();
    expect(played.single.save!.fileName, 'mk.srm');
    expect(played.single.emulator, _target);
  });

  testWidgets('a question that replaces a save starts on Cancel', (tester) async {
    // The save on this PC is on RomM (synced as RomM's save 7): only its time is in question.
    final mine = SaveEntry(source: SaveSource.local, fileName: 'mk.eeprom', savedAt: _day(0, 9, 56), maker: _target,
        tag: _target.tag, sameAsRommId: '7');
    final copy = SaveEntry(source: SaveSource.romm, fileName: 'mine.srm', savedAt: _day(0, 10, 0), maker: _target,
        tag: _target.tag, slot: 'freegosy', rommSave: const {'id': 7});
    await open(tester, remembered: 'retroarch', catalog: SaveCatalog(
        thisPc: [mine], backups: const [], romm: [_g(copy), _g(_romm('mk.srm', _other, _day(3, 18, 40)))], rommOffline: false));
    await tester.ensureVisible(find.text('mk.srm'));
    await tester.tap(find.text('mk.srm'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();

    expect(find.text('Play an older save?'), findsOneWidget);
    expect(Focus.of(tester.element(find.text('Cancel'))).hasFocus, isTrue);
  });

  testWidgets('turning Remember off for the remembered emulator forgets it', (tester) async {
    await open(tester, remembered: 'retroarch', catalog: catalog);
    await tester.tap(find.byKey(const ValueKey('remember-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();
    expect(played.single.forget, isTrue);
    expect(played.single.remember, isFalse);
  });

  testWidgets('Play leaves the remembered emulator alone', (tester) async {
    await open(tester, remembered: 'retroarch', catalog: catalog);
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();
    expect(played.single.forget, isFalse);
  });

  testWidgets('the play screen stays open when the game did not start', (tester) async {
    starts = false;
    await open(tester, remembered: 'retroarch', catalog: catalog);
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();
    expect(played, hasLength(1));
    expect(find.byType(PlayScreen), findsOneWidget);
  });

  testWidgets('opened on the states, a state of another emulator than the remembered one is chosen, in its emulator',
      (tester) async {
    final duckState = ResumeEntry(emulatorId: 'duckstation', emulatorName: 'DuckStation', fileName: 'd1',
        slot: const NumberedStateSlot(1), savedAt: _day(0, 22, 0), where: ResumeWhere.thisPc);
    await open(tester, remembered: 'retroarch', catalog: catalog, states: [duckState], initialTab: 1);
    expect(find.text('⟳ Resume'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();
    expect(resumed.single.fileName, 'd1');
  });

  testWidgets('opened on the states, states listed after the saves are still chosen', (tester) async {
    final later = StreamController<List<ResumeEntry>>();
    addTearDown(later.close);
    await open(tester, remembered: 'retroarch', catalog: catalog, initialTab: 1, statesLater: later.stream);
    later.add([
      ResumeEntry(emulatorId: 'retroarch', emulatorName: 'RetroArch', fileName: 's1', slot: const NumberedStateSlot(1),
          savedAt: _day(1, 22, 0), where: ResumeWhere.thisPc),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('⟳ Resume'), findsOneWidget);
  });

  testWidgets('opened on the states, the newest state is chosen even when the save is newer', (tester) async {
    final state = ResumeEntry(emulatorId: 'retroarch', emulatorName: 'RetroArch', fileName: 's1', slot: const NumberedStateSlot(1),
        savedAt: _day(1, 21, 40), where: ResumeWhere.thisPc);
    await open(tester, remembered: 'retroarch', catalog: catalog, states: [state], initialTab: 1);
    expect(find.text('⟳ Resume'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();
    // Older than the save on this PC: asked first.
    expect(find.text('Resume an older state?'), findsOneWidget);
    await tester.tap(find.text('Resume anyway'));
    await tester.pumpAndSettle();
    expect(resumed.single.fileName, 's1');
  });

  testWidgets('a newer state is preselected and Play reads Resume', (tester) async {
    final state = ResumeEntry(emulatorId: 'retroarch', emulatorName: 'RetroArch', fileName: 's1', slot: const NumberedStateSlot(1),
        savedAt: _day(0, 21, 40), where: ResumeWhere.thisPc);
    await open(tester, remembered: 'retroarch', catalog: catalog, states: [state]);
    expect(find.text('⟳ Resume'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();
    expect(resumed.single.fileName, 's1');
  });

  testWidgets('Show all shows the hidden save, greyed', (tester) async {
    await open(tester, remembered: 'retroarch', catalog: catalog);
    await tester.tap(find.byKey(const ValueKey('show-all')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('fold-backups')));
    await tester.tap(find.byKey(const ValueKey('fold-backups')));
    await tester.pumpAndSettle();
    expect(find.text('ra-backup.zip'), findsOneWidget);
  });

  testWidgets('with no remembered emulator, Any is picked and nothing is hidden', (tester) async {
    await open(tester, catalog: catalog);
    expect(find.text('Any'), findsOneWidget);
    expect(find.textContaining('hidden'), findsNothing);
  });

  testWidgets('no saves anywhere: Play still starts the game, with no save', (tester) async {
    await open(tester, remembered: 'retroarch');
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();
    expect(played.single.emulator, _target);
    expect(played.single.save, isNull);
  });

  testWidgets('LB/RB switch Saves and States; B closes only the play screen', (tester) async {
    await open(tester, remembered: 'retroarch', catalog: catalog);
    inputActionBus.add(GameAction.r1);
    await tester.pumpAndSettle();
    expect(find.text('No save states'), findsOneWidget);
    inputActionBus.add(GameAction.l1);
    await tester.pumpAndSettle();
    expect(find.text('mk.srm'), findsOneWidget);
    inputActionBus.add(GameAction.back);
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('B closes the emulator picker, not the play screen', (tester) async {
    await open(tester, remembered: 'retroarch', catalog: catalog);
    inputActionBus.add(GameAction.favorite);
    await tester.pumpAndSettle();
    expect(find.text('Emulator'), findsWidgets);
    expect(find.text('Any'), findsOneWidget);
    inputActionBus.add(GameAction.back);
    await tester.pumpAndSettle();
    expect(find.text('Any'), findsNothing);
    expect(find.byType(PlayScreen), findsOneWidget);
  });

  testWidgets('Play waits until the saves are listed', (tester) async {
    final appPrefs = SharedPreferencesAppPreferences(prefs);
    final registry = StrategyRegistry(DirectoryService(appPrefs), appPrefs);
    await registry.setGameEmulatorPreference(_game.id, 'retroarch');
    final never = Completer<SaveCatalog>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        strategyRegistryProvider.overrideWith((ref) async => registry),
        emulatorStatusProvider.overrideWith((ref) async => {'retroarch': true}),
        saveCatalogProvider.overrideWith((ref, key) => never.future),
        resumeEntriesProvider.overrideWith((ref, key) => Stream.value(const [])),
        resumeServiceProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(home: PlayScreen(game: _game, coverUrl: '', onPlay: (r) async => (played..add(r)).isNotEmpty)),
    ));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pump();
    expect(played, isEmpty);
  });

  testWidgets('Back to game closes the play screen; Back to library goes all the way back', (tester) async {
    await open(tester, remembered: 'retroarch', catalog: catalog);
    await tester.tap(find.byKey(const ValueKey('back-to-game')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('back-to-library')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsNothing);
    expect(find.text('open'), findsOneWidget, reason: 'the first route: the library');
  });

  testWidgets('starting the save on this PC passes RomM\'s copy of it, so RomM is told this device has it', (tester) async {
    final mine = SaveEntry(source: SaveSource.local, fileName: 'mk.srm', savedAt: DateTime(2026, 9, 28), maker: _target,
        tag: _target.tag, contentHashes: const {'same'});
    final copy = SaveEntry(source: SaveSource.romm, fileName: 'mk.srm', savedAt: DateTime(2026, 9, 29), maker: _target,
        tag: _target.tag, slot: 'freegosy', rommSave: {'id': 5, 'content_hash': 'same'});
    await open(tester, remembered: 'retroarch', catalog: SaveCatalog(thisPc: [mine], backups: const [], rommOffline: false,
        romm: [RommSaveGroup(slot: 'freegosy', tag: _target.tag, newest: copy, older: const [])]));
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();
    expect(played.single.save, isNull, reason: 'the save on this PC');
    expect(played.single.rommCopy?['id'], 5);
  });

  testWidgets('while the save list reloads (e.g. right after a session), Play waits', (tester) async {
    var hang = false;
    final appPrefs = SharedPreferencesAppPreferences(prefs);
    final registry = StrategyRegistry(DirectoryService(appPrefs), appPrefs);
    await registry.setGameEmulatorPreference(_game.id, 'retroarch');
    final never = Completer<SaveCatalog>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        strategyRegistryProvider.overrideWith((ref) async => registry),
        emulatorStatusProvider.overrideWith((ref) async => {'retroarch': true, 'duckstation': true}),
        saveCatalogProvider.overrideWith((ref, key) => hang ? never.future : Future.value(catalog)),
        resumeEntriesProvider.overrideWith((ref, key) => Stream.value(const [])),
        resumeServiceProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(home: PlayScreen(game: _game, coverUrl: '', onPlay: (r) async => (played..add(r)).isNotEmpty)),
    ));
    await tester.pumpAndSettle();
    // A session ends: the list is re-read, and that takes a while.
    hang = true;
    ProviderScope.containerOf(tester.element(find.byType(PlayScreen)))
        .invalidate(saveCatalogProvider(SaveCatalogKey(_game)));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SaveWaiting), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pump();
    expect(played, isEmpty);
  });

  testWidgets('RomM offline says so', (tester) async {
    await open(tester, remembered: 'retroarch',
        catalog: SaveCatalog(thisPc: [_local(DateTime(2026, 10, 1))], backups: const [], romm: const [], rommOffline: true));
    expect(find.textContaining('RomM is offline'), findsOneWidget);
  });

  testWidgets('the wide layout shows the three panels', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester, remembered: 'retroarch', catalog: catalog);
    expect(find.text('⚙ SETTINGS'), findsOneWidget);
    expect(find.byKey(const ValueKey('play-main')), findsOneWidget);
  });
}
