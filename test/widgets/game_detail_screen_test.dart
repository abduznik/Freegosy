import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/ui/widgets/focus_effect_wrapper.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/input/gamepad_service.dart';
import 'package:freegosy/core/input/input_action_bus.dart';
import 'package:freegosy/core/romm/romm_models.dart';
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
import 'package:freegosy/providers/ui_provider.dart';
import 'package:freegosy/ui/screens/game_detail_screen.dart';
import 'package:freegosy/ui/screens/play_screen.dart';
import 'package:freegosy/ui/widgets/controller_hints_bar.dart';
import 'package:freegosy/ui/widgets/game_detail/saves_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _game = Game(id: '7', name: 'Mario Kart 64', fsName: 'mk', fsExtension: 'z64', platformSlug: 'n64', fileSize: 1, files: const []);
final _windowsGame = Game(id: '8', name: 'Doom', fsName: 'doom', platformSlug: 'win', fileSize: 1, files: const []);

ResumeEntry _state(DateTime t) => ResumeEntry(emulatorId: 'ares', emulatorName: 'ares', fileName: 's1',
    slot: const NumberedStateSlot(1), savedAt: t, where: ResumeWhere.thisPc);

void main() {
  late SharedPreferences prefs;
  late List<String> log;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    log = [];
  });

  Future<void> pump(WidgetTester tester,
      {Game? game, bool downloaded = true, List<ResumeEntry> states = const [], DateTime? newestSave,
      Future<void> Function(ResumeEntry e)? onResume, String? remembered, bool pushed = false, InputMode inputMode = InputMode.mouse, RommService? rommService,
      List<RommSaveGroup> romm = const []}) async {
    final appPrefs = SharedPreferencesAppPreferences(prefs);
    final registry = StrategyRegistry(DirectoryService(appPrefs), appPrefs);
    if (remembered != null) await registry.setGameEmulatorPreference((game ?? _game).id, remembered);
    final page = GameDetailScreen(
      game: game ?? _game,
      rommBaseUrl: 'https://romm.example.com',
      isDownloaded: downloaded,
      onPlay: (r) async => (log..add('play ${r.emulator}')).isNotEmpty,
      onDownload: (g) async => log.add('download'),
      onPushSaves: () async => log.add('push'),
      onDelete: () async => log.add('delete'),
      onConfigure: () async => log.add('configure'),
      onResume: onResume ?? (e) async => log.add('resume ${e.fileName}'),
      rommService: rommService,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        romScannerServiceProvider.overrideWithValue(null),
        directoryServiceProvider.overrideWith((ref) async => null),
        strategyRegistryProvider.overrideWith((ref) async => registry),
        emulatorStatusProvider.overrideWith((ref) async => {'ares': true}),
        resumeEntriesProvider.overrideWith((ref, key) => Stream.value(states)),
        resumeServiceProvider.overrideWith((ref) async => null),
        saveCatalogProvider.overrideWith((ref, key) async => SaveCatalog(
              thisPc: [
                if (newestSave != null)
                  SaveEntry(source: SaveSource.local, fileName: 'mk.eeprom', savedAt: newestSave, maker: const SaveMaker('ares'), tag: 'ares'),
              ],
              backups: const [],
              romm: romm,
              rommOffline: false,
            )),
        inputModeProvider.overrideWith((ref) => inputMode),
      ],
      child: MaterialApp(
        home: pushed
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
                    child: const Text('library'),
                  ),
                ),
              )
            : page,
      ),
    ));
    if (pushed) {
      await tester.pumpAndSettle();
      await tester.tap(find.text('library'));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('a downloaded game: ▶ Play opens the play screen', (tester) async {
    await pump(tester);
    expect(find.text('▶ Play'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('play-button')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsOneWidget);
  });

  testWidgets('the back button returns to the library', (tester) async {
    await pump(tester, pushed: true);
    expect(find.byType(GameDetailScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('back-button')));
    await tester.pumpAndSettle();
    expect(find.byType(GameDetailScreen), findsNothing);
    expect(find.text('library'), findsOneWidget);
  });

  testWidgets('a screenshot shows as a banner at the top of the page', (tester) async {
    await pump(tester, game: Game(id: '9', name: 'Zelda', fsName: 'z', platformSlug: 'n64', fileSize: 1, files: const [],
        screenshotUrl: 'https://example.com/z.jpg'));
    expect(find.byKey(const ValueKey('game-banner')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('game-banner'))).dy, 0);
  });

  testWidgets('no screenshot, no banner', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('game-banner')), findsNothing);
  });

  testWidgets('▶ Play has the same colour as the other buttons', (tester) async {
    await pump(tester);
    Color? colourOf(String key) => (tester
            .widget<Container>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Container)).last)
            .decoration as BoxDecoration)
        .color;
    expect(colourOf('play-button'), colourOf('more-button'));
  });

  testWidgets('a game not on disk: ⭳ Download', (tester) async {
    await pump(tester, downloaded: false);
    expect(find.text('⭳ Download'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('download-button')));
    await tester.pumpAndSettle();
    expect(log, ['download']);
  });

  testWidgets('⋯ holds Open folder and Delete; Configure only for Windows games', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('more-button')));
    await tester.pumpAndSettle();
    expect(find.text('Open folder'), findsOneWidget);
    expect(find.text('Delete from this PC'), findsOneWidget);
    expect(find.text('Configure'), findsNothing);
    expect(find.text('Forget launch choice'), findsNothing);
    await tester.tap(find.text('Delete from this PC'));
    await tester.pumpAndSettle();
    expect(log, ['delete']);
  });

  testWidgets('⋯ holds Configure for a Windows game', (tester) async {
    await pump(tester, game: _windowsGame);
    await tester.tap(find.byKey(const ValueKey('more-button')));
    await tester.pumpAndSettle();
    expect(find.text('Configure'), findsOneWidget);
  });

  testWidgets('Forget launch choice shows when an emulator is remembered', (tester) async {
    await pump(tester, remembered: 'ares');
    await tester.tap(find.byKey(const ValueKey('more-button')));
    await tester.pumpAndSettle();
    expect(find.text('Forget launch choice'), findsOneWidget);
  });

  testWidgets('tabs, and LB/RB switch between them', (tester) async {
    await pump(tester);
    expect(find.byType(SavesTab), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab-saves')));
    await tester.pumpAndSettle();
    expect(find.byType(SavesTab), findsOneWidget);
    inputActionBus.add(GameAction.r1);
    await tester.pumpAndSettle();
    expect(find.byType(SavesTab), findsNothing);
    inputActionBus.add(GameAction.l1);
    await tester.pumpAndSettle();
    expect(find.byType(SavesTab), findsOneWidget);
  });

  testWidgets('on the Saves tab the hints say X restores and holding A deletes', (tester) async {
    await pump(tester, inputMode: InputMode.gamepad);
    final hints = find.byType(ControllerHintsBar);
    expect(find.descendant(of: hints, matching: find.text('Restore')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab-saves')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: hints, matching: find.text('Restore')), findsOneWidget);
    expect(find.descendant(of: hints, matching: find.text('Delete')), findsOneWidget);
  });

  testWidgets('a RomM save that could not be deleted says so', (tester) async {
    final save = SaveEntry(source: SaveSource.romm, fileName: 'mk.srm', savedAt: DateTime(2026, 9, 1),
        maker: const SaveMaker('ares'), tag: 'ares', slot: 'freegosy', rommSave: const {'id': 3});
    await pump(tester, rommService: _RefusingRomm(),
        romm: [RommSaveGroup(slot: 'freegosy', tag: 'ares', newest: save, older: const [])]);
    await tester.tap(find.byKey(const ValueKey('tab-saves')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FocusEffectWrapper, 'Delete').last);
    await tester.pumpAndSettle();

    expect(find.text("Couldn't delete"), findsOneWidget);
  });

  testWidgets('Y opens the play screen on the states, the newest chosen; A there resumes it', (tester) async {
    await pump(tester, states: [_state(DateTime(2026, 10, 1, 21))], newestSave: DateTime(2026, 10, 1, 9));
    inputActionBus.add(GameAction.favorite);
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsOneWidget);
    expect(find.text('⟳ Resume'), findsOneWidget);
    expect(log, isEmpty, reason: 'nothing starts until A');
    await tester.tap(find.byKey(const ValueKey('play-main')));
    await tester.pumpAndSettle();
    expect(log, ['resume s1']);
  });

  testWidgets('Y with no states does nothing', (tester) async {
    await pump(tester);
    inputActionBus.add(GameAction.favorite);
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsNothing);
  });

  testWidgets('B closes the ⋯ menu', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('more-button')));
    await tester.pumpAndSettle();
    inputActionBus.add(GameAction.back);
    await tester.pumpAndSettle();
    expect(find.text('Open folder'), findsNothing);
    expect(find.byType(GameDetailScreen), findsOneWidget);
  });

  testWidgets('Y twice opens one play screen', (tester) async {
    await pump(tester, states: [_state(DateTime(2026, 10, 1, 21))]);
    inputActionBus.add(GameAction.favorite);
    await tester.pump();
    inputActionBus.add(GameAction.favorite);
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsOneWidget);
  });

  testWidgets('B on the play screen closes only the play screen', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('play-button')));
    await tester.pumpAndSettle();
    inputActionBus.add(GameAction.back);
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsNothing);
    expect(find.byType(GameDetailScreen), findsOneWidget);
  });
}

/// RomM that refuses to delete.
class _RefusingRomm extends Fake implements RommService {
  @override
  Future<bool> deleteSaves(List<int> saveIds) async => false;
}
