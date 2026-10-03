import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/input/gamepad_service.dart';
import 'package:freegosy/core/input/input_action_bus.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/catalog/save_catalog.dart';
import 'package:freegosy/core/save/catalog/save_entry.dart';
import 'package:freegosy/core/save/catalog/save_maker.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:freegosy/providers/resume_provider.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:freegosy/providers/save_catalog_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/ui/widgets/game_detail/saves_tab.dart';
import 'package:freegosy/ui/widgets/save_list/save_waiting.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _game = Game(id: '7', name: 'Mario Kart 64', fsName: 'mk', platformSlug: 'n64', fileSize: 0);
const _ares = SaveMaker('ares');
const _mupen = SaveMaker('retroarch', coreId: 'mupen64plus_next');

void main() {
  late List<String> log;
  // When set, re-reading the save list never finishes.
  var hang = false;
  final never = Completer<SaveCatalog>();

  Future<void> pump(WidgetTester tester, {String? remembered, Game? game, SaveCatalog? catalog}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final appPrefs = SharedPreferencesAppPreferences(prefs);
    final registry = StrategyRegistry(DirectoryService(appPrefs), appPrefs);
    if (remembered != null) await registry.setGameEmulatorPreference((game ?? _game).id, remembered);
    log = [];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        strategyRegistryProvider.overrideWith((ref) async => registry),
        emulatorStatusProvider.overrideWith((ref) async => {'ares': true, 'retroarch': true, 'duckstation': true}),
        saveCatalogProvider.overrideWith((ref, key) async => hang ? never.future : catalog ?? SaveCatalog(
              thisPc: [SaveEntry(source: SaveSource.local, fileName: 'mk.eeprom', savedAt: DateTime(2026, 10, 1), maker: _ares, tag: 'ares')],
              backups: const [],
              romm: [
                RommSaveGroup(slot: 'freegosy', tag: 'ares', older: const [],
                    newest: SaveEntry(source: SaveSource.romm, fileName: 'old.eeprom', savedAt: DateTime(2026, 9, 1), maker: _ares, tag: 'ares', slot: 'freegosy', rommSave: const {'id': 3})),
                RommSaveGroup(slot: 'f2', tag: 'mupen64plus_next', older: const [],
                    newest: SaveEntry(source: SaveSource.romm, fileName: 'new.srm', savedAt: DateTime(2026, 10, 2), maker: _mupen, tag: 'mupen64plus_next', slot: 'f2', rommSave: const {'id': 4})),
                RommSaveGroup(slot: 'f3', tag: 'freegosy', older: const [],
                    newest: SaveEntry(source: SaveSource.romm, fileName: 'zip.zip', savedAt: DateTime(2026, 10, 3), tag: 'freegosy', slot: 'f3', rommSave: const {'id': 5})),
              ],
              rommOffline: false,
            )),
        resumeEntriesProvider.overrideWith((ref, key) => Stream.value(const [])),
        resumeServiceProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SavesTab(
              game: game ?? _game,
              onPush: () async => log.add('push'),
              onBackupNow: () async => log.add('backup'),
              onRestore: (s, target) async => log.add('restore ${s.fileName} -> $target'),
              onDelete: (s) async => log.add('delete ${s.fileName}'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Push to RomM and Backup now', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('push-to-romm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('backup-now')));
    await tester.pumpAndSettle();
    expect(log, ['push', 'backup']);
  });

  testWidgets('restoring a newer RomM save goes straight into the emulator that made it', (tester) async {
    await pump(tester);
    await tester.tap(find.descendant(
        of: find.byKey(ValueKey('save-row-new.srm-${DateTime(2026, 10, 2).millisecondsSinceEpoch}')),
        matching: find.byTooltip('Restore to this PC')));
    await tester.pumpAndSettle();
    expect(log, ['restore new.srm -> retroarch/mupen64plus_next']);
  });

  testWidgets('restoring an older save asks first', (tester) async {
    await pump(tester);
    await tester.tap(find.descendant(
        of: find.byKey(ValueKey('save-row-old.eeprom-${DateTime(2026, 9, 1).millisecondsSinceEpoch}')),
        matching: find.byTooltip('Restore to this PC')));
    await tester.pumpAndSettle();
    // The save on this PC was never uploaded: that question comes first.
    expect(find.text("Your save on this PC isn't on RomM"), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(log, ['restore old.eeprom -> ares']);
  });

  testWidgets('a save of unknown maker is restored into the remembered emulator of the game', (tester) async {
    await pump(tester, remembered: 'ares');
    await tester.tap(find.descendant(
        of: find.byKey(ValueKey('save-row-zip.zip-${DateTime(2026, 10, 3).millisecondsSinceEpoch}')),
        matching: find.byTooltip('Restore to this PC')));
    await tester.pumpAndSettle();
    // ares's save on this PC was never uploaded: confirm replacing it.
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(log, ['restore zip.zip -> ares']);
  });

  testWidgets('a save that converts is restored into the emulator the game plays in', (tester) async {
    // RetroArch remembered for a PS1 game; DuckStation's card converts for its cores.
    final ps1 = Game(id: '8', name: 'Crash', fsName: 'crash', platformSlug: 'psx', fileSize: 0);
    final card = SaveEntry(source: SaveSource.romm, fileName: 'crash.mcd', savedAt: DateTime(2026, 10, 2),
        maker: const SaveMaker('duckstation'), tag: 'duckstation', slot: 'freegosy', rommSave: const {'id': 9});
    await pump(tester, remembered: 'retroarch', game: ps1, catalog: SaveCatalog(thisPc: const [], backups: const [],
        romm: [RommSaveGroup(slot: 'freegosy', tag: 'duckstation', newest: card, older: const [])], rommOffline: false));
    await tester.tap(find.byTooltip('Restore to this PC'));
    await tester.pumpAndSettle();
    expect(log.single, startsWith('restore crash.mcd -> retroarch/'));
  });

  testWidgets('the question names the emulator, not its id', (tester) async {
    final ps1 = Game(id: '8', name: 'Crash', fsName: 'crash', platformSlug: 'psx', fileSize: 0);
    final card = SaveEntry(source: SaveSource.romm, fileName: 'crash.mcd', savedAt: DateTime(2026, 10, 2),
        maker: const SaveMaker('duckstation'), tag: 'duckstation', slot: 'freegosy', rommSave: const {'id': 9});
    await pump(tester, remembered: 'duckstation', game: ps1, catalog: SaveCatalog(
        thisPc: [SaveEntry(source: SaveSource.local, fileName: 'crash.mcd', savedAt: DateTime(2026, 10, 1),
            maker: const SaveMaker('duckstation'), tag: 'duckstation')],
        backups: const [],
        romm: [RommSaveGroup(slot: 'freegosy', tag: 'duckstation', newest: card, older: const [])],
        rommOffline: false));
    await tester.tap(find.byTooltip('Restore to this PC'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your DuckStation save'), findsOneWidget);
  });

  testWidgets('a save that can\'t convert still goes back into the emulator that made it', (tester) async {
    // ares remembered: RetroArch's N64 save doesn't convert for it.
    await pump(tester, remembered: 'ares');
    await tester.tap(find.descendant(
        of: find.byKey(ValueKey('save-row-new.srm-${DateTime(2026, 10, 2).millisecondsSinceEpoch}')),
        matching: find.byTooltip('Restore to this PC')));
    await tester.pumpAndSettle();
    expect(log, ['restore new.srm -> retroarch/mupen64plus_next']);
  });

  testWidgets('while the save list reloads (e.g. right after a session), nothing can be restored', (tester) async {
    await pump(tester);
    hang = true;
    addTearDown(() => hang = false);
    ProviderScope.containerOf(tester.element(find.byType(SavesTab)))
        .invalidate(saveCatalogProvider(SaveCatalogKey(_game)));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SaveWaiting), findsOneWidget);
    expect(find.byTooltip('Restore to this PC'), findsNothing);
  });

  testWidgets('B cancels the delete question', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    inputActionBus.add(GameAction.back);
    await tester.pumpAndSettle();
    expect(find.text('Delete this save?'), findsNothing);
    expect(log, isEmpty);
  });

  testWidgets('deleting asks first', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete this save?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(log.single, startsWith('delete '));
  });
}
