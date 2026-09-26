import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/input/gamepad_service.dart';
import 'package:freegosy/core/input/input_action_bus.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/resume_service.dart';
import 'package:freegosy/core/save/save_state_info.dart';
import 'package:freegosy/providers/resume_provider.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/providers/ui_provider.dart';
import 'package:freegosy/ui/screens/game_detail_screen.dart';
import 'package:freegosy/ui/widgets/game_detail/game_action_button.dart';
import 'package:freegosy/ui/widgets/game_detail/resume_split_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _game = Game(
  id: '4242',
  name: 'Test Game',
  fsName: 'test game',
  fsExtension: 'iso',
  fileSize: 1024,
  files: const [],
);

final _auto = ResumeEntry(
  emulatorId: 'emu',
  emulatorName: 'Emu',
  fileName: 'auto.state',
  slot: const AutoStateSlot(),
  savedAt: DateTime(2026, 9, 21, 21, 10),
  where: ResumeWhere.thisPc,
  emulatorVersion: 'v2.8.2',
  installedVersion: '2.8.2.0',
  compat: StateCompat.ok,
);

final _slot3 = ResumeEntry(
  emulatorId: 'emu',
  emulatorName: 'Emu',
  fileName: 'slot3.state',
  slot: const NumberedStateSlot(3),
  savedAt: DateTime(2026, 9, 12, 18, 0),
  where: ResumeWhere.romm,
  compat: StateCompat.unknown,
);

final _slot1 = ResumeEntry(
  emulatorId: 'emu',
  emulatorName: 'Emu',
  fileName: 'slot1.state',
  slot: const NumberedStateSlot(1),
  savedAt: DateTime(2026, 9, 1, 12, 0),
  where: ResumeWhere.thisPc,
  emulatorVersion: 'v2.6.0',
  installedVersion: '2.8.2.0',
  compat: StateCompat.mismatch,
);

void main() {
  late SharedPreferences prefs;
  late int launches;
  late List<ResumeEntry> resumed;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    launches = 0;
    resumed = [];
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<ResumeEntry> entries = const [],
    InputMode inputMode = InputMode.mouse,
    Stream<List<ResumeEntry>> Function(Ref ref)? entriesStream,
    Future<void> Function(ResumeEntry entry)? onResume,
    Future<void> Function()? onLaunch,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          romScannerServiceProvider.overrideWithValue(null),
          directoryServiceProvider.overrideWith((ref) async => null),
          resumeEntriesProvider.overrideWith(
              (ref, key) => entriesStream?.call(ref) ?? Stream.value(entries)),
          resumeServiceProvider.overrideWith((ref) async => null),
          inputModeProvider.overrideWith((ref) => inputMode),
        ],
        child: MaterialApp(
          home: GameDetailScreen(
            game: _game,
            rommBaseUrl: 'https://romm.example.com',
            isDownloaded: true,
            onLaunch: onLaunch ?? () async => launches++,
            onDownload: (game) async {},
            onPushSaves: () {},
            onPullSaves: () {},
            onDelete: () {},
            onResume: onResume ?? (entry) async => resumed.add(entry),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool focusWithin(WidgetTester tester, Finder finder) {
    final target = tester.element(finder);
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    if (focused == target) return true;
    var found = false;
    focused.visitAncestorElements((e) {
      if (e == target) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  testWidgets('no entries: the page is as before', (tester) async {
    await pumpScreen(tester, inputMode: InputMode.gamepad);
    expect(find.text('Play Game'), findsOneWidget);
    expect(find.textContaining('Resume Game'), findsNothing);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('entries: Resume Game shows the newest time, Play Game (fresh start) below', (tester) async {
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1]);
    expect(find.textContaining('Resume Game'), findsOneWidget);
    expect(find.textContaining('21 Sep 21:10'), findsOneWidget);
    expect(find.text('Play Game'), findsOneWidget);
    expect(find.text('(fresh start)'), findsOneWidget);
    final resumeY = tester.getTopLeft(find.textContaining('Resume Game')).dy;
    final playY = tester.getTopLeft(find.text('Play Game')).dy;
    expect(resumeY, lessThan(playY));
  });

  testWidgets('Play Game is as tall as Resume Game', (tester) async {
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1]);
    final resumeHeight = tester.getSize(find.byKey(const Key('resume-main'))).height;
    final slotsHeight = tester.getSize(find.byKey(const Key('resume-slots'))).height;
    final playHeight = tester
        .getSize(find.ancestor(of: find.text('Play Game'), matching: find.byType(GameActionButton)))
        .height;
    expect(playHeight, resumeHeight);
    expect(slotsHeight, resumeHeight);
  });

  testWidgets('Resume stays while its list reloads after a dependency changes', (tester) async {
    // A dependency change (e.g. RomM going offline) rebuilds the list provider
    // non-seamlessly: it is loading again, with the previous list kept.
    final generation = StateProvider<int>((ref) => 0);
    final neverAnswers = StreamController<List<ResumeEntry>>();
    addTearDown(neverAnswers.close);
    await pumpScreen(tester,
        entriesStream: (ref) =>
            ref.watch(generation) == 0 ? Stream.value([_auto]) : neverAnswers.stream);
    expect(find.byType(ResumeSplitButton), findsOneWidget);

    ProviderScope.containerOf(tester.element(find.byType(GameDetailScreen)))
        .read(generation.notifier)
        .state = 1;
    await tester.pump();
    await tester.pump();

    expect(find.byType(ResumeSplitButton), findsOneWidget,
        reason: 'the previous list stays on screen while the new one loads');
  });

  testWidgets('a list arriving late does not pull focus from a button the user moved to',
      (tester) async {
    final arriving = StreamController<List<ResumeEntry>>();
    addTearDown(arriving.close);
    await pumpScreen(tester, entriesStream: (_) => arriving.stream);
    final pushSaves = Focus.of(tester.element(find.text('Push Saves')));
    pushSaves.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, pushSaves);

    arriving.add([_auto]);
    await tester.pumpAndSettle();

    expect(find.byType(ResumeSplitButton), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, pushSaves);
  });

  testWidgets('Resume has focus when the page opens', (tester) async {
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1]);
    expect(focusWithin(tester, find.byKey(const Key('resume-main'))), isTrue);
  });

  testWidgets('pressing Resume calls onResume with the newest entry', (tester) async {
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1]);
    await tester.tap(find.byKey(const Key('resume-main')));
    await tester.pumpAndSettle();
    expect(resumed, [_auto]);
    expect(launches, 0);
  });

  testWidgets('▾ opens the slot list; rows show label, where, version and the ⚠ line', (tester) async {
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1]);
    await tester.tap(find.byKey(const Key('resume-slots')));
    await tester.pumpAndSettle();
    expect(find.text('Resume (saved on exit)'), findsOneWidget);
    expect(find.text('Slot 3'), findsOneWidget);
    expect(find.text('Slot 1'), findsOneWidget);
    expect(find.textContaining('RomM'), findsOneWidget);
    expect(find.textContaining('this PC'), findsNWidgets(2));
    expect(find.textContaining('21 Sep 21:10 · Emu v2.8.2 · this PC'), findsOneWidget);
    expect(find.textContaining('version unknown'), findsOneWidget);
    expect(find.text('Made with v2.6.0, you have 2.8.2.0. May not load.'), findsOneWidget);
  });

  testWidgets('picking a row calls onResume with that entry', (tester) async {
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1]);
    await tester.tap(find.byKey(const Key('resume-slots')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slot 1'));
    await tester.pumpAndSettle();
    expect(resumed, [_slot1]);
    expect(find.text('Slot 3'), findsNothing);
  });

  testWidgets('X (GameAction.detail) opens the slot list', (tester) async {
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1]);
    inputActionBus.add(GameAction.detail);
    await tester.pumpAndSettle();
    expect(find.text('Slot 3'), findsOneWidget);
  });

  testWidgets('X does not open the slot list while another dialog is on top of the page',
      (tester) async {
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1]);
    final pageContext = tester.element(find.byType(GameDetailScreen));
    unawaited(showDialog<void>(
      context: pageContext,
      builder: (_) => const AlertDialog(title: Text('Blocking dialog')),
    ));
    await tester.pump();
    expect(find.text('Blocking dialog'), findsOneWidget);

    inputActionBus.add(GameAction.detail);
    await tester.pumpAndSettle();

    expect(find.text('Slot 3'), findsNothing);
    expect(find.text('Blocking dialog'), findsOneWidget);
  });

  testWidgets('hints show A Resume and X Slots when there are entries', (tester) async {
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1], inputMode: InputMode.gamepad);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Slots'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
  });

  testWidgets('a newest entry with a mismatch shows ⚠ on the Resume button', (tester) async {
    await pumpScreen(tester, entries: [_slot1, _slot3]);
    expect(
      find.descendant(
        of: find.byType(ResumeSplitButton),
        matching: find.byIcon(Icons.warning_amber_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no ⚠ on the Resume button when the newest entry is ok', (tester) async {
    await pumpScreen(tester, entries: [_auto, _slot1]);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('Play still calls onLaunch', (tester) async {
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1]);
    await tester.tap(find.text('Play Game'));
    await tester.pumpAndSettle();
    expect(launches, 1);
    expect(resumed, isEmpty);
  });
  testWidgets('while a Resume launch is still running, Resume, Play, a slot pick and X do nothing',
      (tester) async {
    var pending = Completer<void>();
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1], onResume: (entry) {
      resumed.add(entry);
      return pending.future;
    });

    await tester.tap(find.byKey(const Key('resume-main')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('resume-main')));
    await tester.pump();
    await tester.tap(find.text('Play Game'));
    await tester.pump();
    inputActionBus.add(GameAction.detail);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('resume-slots')));
    await tester.pumpAndSettle();

    expect(resumed, [_auto], reason: 'one launch at a time');
    expect(launches, 0);
    expect(find.text('Slot 3'), findsNothing, reason: 'no slot list while a launch runs');

    pending.complete();
    await tester.pumpAndSettle();
    pending = Completer<void>();
    await tester.tap(find.byKey(const Key('resume-main')));
    await tester.pump();
    expect(resumed, [_auto, _auto], reason: 'a finished launch frees the page again');
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('while a Play launch is still running, Play and Resume do nothing', (tester) async {
    var pending = Completer<void>();
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1], onLaunch: () {
      launches++;
      return pending.future;
    });

    await tester.tap(find.text('Play Game'));
    await tester.pump();
    await tester.tap(find.text('Play Game'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('resume-main')));
    await tester.pump();

    expect(launches, 1);
    expect(resumed, isEmpty);

    pending.complete();
    await tester.pumpAndSettle();
    pending = Completer<void>();
    await tester.tap(find.text('Play Game'));
    await tester.pump();
    expect(launches, 2);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a launch picked from the slot list also blocks Resume until it ends', (tester) async {
    final pending = Completer<void>();
    await pumpScreen(tester, entries: [_auto, _slot3, _slot1], onResume: (entry) {
      resumed.add(entry);
      return pending.future;
    });

    await tester.tap(find.byKey(const Key('resume-slots')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slot 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('resume-main')));
    await tester.pump();

    expect(resumed, [_slot1]);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('without Resume entries, Play is still one launch at a time', (tester) async {
    final pending = Completer<void>();
    await pumpScreen(tester, onLaunch: () {
      launches++;
      return pending.future;
    });

    await tester.tap(find.text('Play Game'));
    await tester.pump();
    await tester.tap(find.text('Play Game'));
    await tester.pump();

    expect(launches, 1);
    pending.complete();
    await tester.pumpAndSettle();
  });
}
