import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/input/gamepad_service.dart';
import 'package:freegosy/core/input/input_action_bus.dart';
import 'package:freegosy/core/save/catalog/play_view.dart';
import 'package:freegosy/core/save/catalog/save_catalog.dart';
import 'package:freegosy/core/save/catalog/save_entry.dart';
import 'package:freegosy/core/save/catalog/save_maker.dart';
import 'package:freegosy/providers/ui_provider.dart';
import 'package:freegosy/ui/widgets/save_list/save_list.dart';

void main() {
  const target = SaveMaker('retroarch', coreId: 'pcsx_rearmed');
  const other = SaveMaker('duckstation');

  SaveEntry e(SaveSource s, String name, SaveMaker? m, {int day = 28}) =>
      SaveEntry(source: s, fileName: name, savedAt: DateTime(2026, 9, day), maker: m, tag: m?.tag ?? 'freegosy', sizeBytes: 512);

  // RetroArch's PCSX-ReARMed picked: DuckStation's RomM card converts;
  // DuckStation's backup can't be used (a backup goes back only into its own
  // emulator).
  PlayView view({bool offline = false}) => buildPlayView(
        catalog: SaveCatalog(
          thisPc: [e(SaveSource.local, 'mk.eeprom', target, day: 30)],
          backups: [e(SaveSource.backup, 'b1.zip', target, day: 27), e(SaveSource.backup, 'b-ra.zip', other, day: 26)],
          romm: offline
              ? const []
              : [
                  RommSaveGroup(slot: 'freegosy', tag: 'duckstation',
                      newest: e(SaveSource.romm, 'mk.srm', other, day: 29), older: [e(SaveSource.romm, 'mk-old.srm', other, day: 20)]),
                ],
          rommOffline: offline,
        ),
        states: const [],
        platformSlug: 'psx',
        picked: target,
        platformDefault: other,
        installed: const {'retroarch', 'duckstation'},
        showAll: true,
      );

  Future<void> pump(WidgetTester tester, Widget list) async {
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: list)))));
    await tester.pumpAndSettle();
  }

  testWidgets('This PC and RomM groups, with tags, converted marks and the live-list note', (tester) async {
    await pump(tester, SaveList(view: view(), mode: SaveListMode.choose, onSelect: (_) {}));
    expect(find.text('THIS PC'), findsOneWidget);
    expect(find.text('ROMM'), findsOneWidget);
    expect(find.text('live list · nothing downloaded yet'), findsOneWidget);
    expect(find.text('mk.eeprom'), findsOneWidget);
    expect(find.text('mk.srm'), findsOneWidget);
    expect(find.text('converted'), findsOneWidget);
    expect(find.text('duckstation'), findsOneWidget);
  });

  testWidgets('backups and older versions are folded until opened', (tester) async {
    await pump(tester, SaveList(view: view(), mode: SaveListMode.choose, onSelect: (_) {}));
    expect(find.text('b1.zip'), findsNothing);
    expect(find.text('mk-old.srm'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('fold-backups')));
    await tester.tap(find.byKey(const ValueKey('fold-freegosy|duckstation')));
    await tester.pumpAndSettle();
    expect(find.text('b1.zip'), findsOneWidget);
    expect(find.text('mk-old.srm'), findsOneWidget);
  });

  testWidgets('an unusable save says why, and picking it does nothing', (tester) async {
    final picked = <String>[];
    await pump(tester, SaveList(view: view(), mode: SaveListMode.choose, onSelect: (r) => picked.add(r.entry.fileName)));
    await tester.tap(find.byKey(const ValueKey('fold-backups')));
    await tester.pumpAndSettle();
    expect(find.textContaining('A backup goes back only into duckstation'), findsOneWidget);
    await tester.tap(find.text('b-ra.zip'));
    await tester.tap(find.text('mk.srm'));
    expect(picked, ['mk.srm']);
  });

  testWidgets('manage mode: holding A on a RomM row deletes it', (tester) async {
    final deleted = <String>[];
    await pump(tester, SaveList(view: view(), mode: SaveListMode.manage, onSelect: (_) {}, onDelete: (r) => deleted.add(r.entry.fileName)));
    final row = find.byKey(ValueKey('save-row-mk.srm-${DateTime(2026, 9, 29).millisecondsSinceEpoch}'));
    Focus.of(tester.element(find.descendant(of: row, matching: find.byType(Focus)).last)).requestFocus();
    await tester.pump();
    final hold = ProviderScope.containerOf(tester.element(find.byType(SaveList))).read(focusedLongPressActionProvider);
    expect(hold, isNotNull);
    hold!();
    expect(deleted, ['mk.srm']);
  });

  testWidgets('X does nothing once focus has left the rows, even after the list was rebuilt', (tester) async {
    final restored = <String>[];
    final current = ValueNotifier(view());
    final elsewhere = FocusNode();
    addTearDown(elsewhere.dispose);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              Focus(focusNode: elsewhere, child: const Text('push')),
              ValueListenableBuilder<PlayView>(
                valueListenable: current,
                builder: (_, v, _) => SaveList(
                    view: v, mode: SaveListMode.manage, onSelect: (_) {}, onRestore: (r) => restored.add(r.entry.fileName)),
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey('save-row-mk.srm-${DateTime(2026, 9, 29).millisecondsSinceEpoch}'));
    Focus.of(tester.element(find.descendant(of: row, matching: find.byType(Focus)).last)).requestFocus();
    await tester.pump();
    current.value = view(); // the catalog was re-read: new rows for the same saves
    await tester.pump();
    elsewhere.requestFocus();
    await tester.pump();
    inputActionBus.add(GameAction.detail);
    await tester.pump();
    expect(restored, isEmpty);
  });

  testWidgets('RomM\'s copy of the save on this PC says so', (tester) async {
    final local = SaveEntry(source: SaveSource.local, fileName: 'mine.srm', savedAt: DateTime(2026, 9, 28), maker: target,
        tag: target.tag, contentHashes: const {'hh'});
    final copy = SaveEntry(source: SaveSource.romm, fileName: 'copy.srm', savedAt: DateTime(2026, 9, 29), maker: target,
        tag: target.tag, slot: 'freegosy', rommSave: {'id': 1, 'content_hash': 'hh'});
    final v = buildPlayView(
      catalog: SaveCatalog(thisPc: [local], backups: const [], rommOffline: false,
          romm: [RommSaveGroup(slot: 'freegosy', tag: target.tag, newest: copy, older: const [])]),
      states: const [],
      platformSlug: 'psx',
      picked: target,
      platformDefault: target,
      installed: const {'retroarch'},
    );
    await pump(tester, SaveList(view: v, mode: SaveListMode.choose, onSelect: (_) {}));
    expect(find.text('on this PC'), findsOneWidget);
  });

  testWidgets('RomM offline says so', (tester) async {
    await pump(tester, SaveList(view: view(offline: true), mode: SaveListMode.choose, onSelect: (_) {}));
    expect(find.textContaining('RomM is offline'), findsOneWidget);
  });

  testWidgets('manage mode: restore and delete on RomM rows and backups, X restores the focused row', (tester) async {
    final restored = <String>[], deleted = <String>[];
    await pump(
        tester,
        SaveList(
          view: view(),
          mode: SaveListMode.manage,
          onSelect: (_) {},
          onRestore: (r) => restored.add(r.entry.fileName),
          onDelete: (r) => deleted.add(r.entry.fileName),
        ));
    expect(find.byTooltip('Restore to this PC'), findsOneWidget); // mk.srm (backups folded)
    await tester.tap(find.byTooltip('Delete').first);
    expect(deleted, ['mk.srm']);

    final row = find.byKey(ValueKey('save-row-mk.srm-${DateTime(2026, 9, 29).millisecondsSinceEpoch}'));
    Focus.of(tester.element(find.descendant(of: row, matching: find.byType(Focus)).last)).requestFocus();
    await tester.pump();
    inputActionBus.add(GameAction.detail);
    await tester.pump();
    expect(restored, ['mk.srm']);
  });
}
