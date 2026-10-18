import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/discover.dart';
import 'package:freegosy/providers/paginated_games_provider.dart';
import 'package:freegosy/ui/widgets/filter_bottom_sheet.dart';

Future<void> _reveal(WidgetTester tester, Finder target) => tester.scrollUntilVisible(
      target,
      150,
      scrollable: find
          .descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable))
          .first,
    );

Future<ActiveFilters?> _openSheet(WidgetTester tester, {ActiveFilters current = const ActiveFilters()}) async {
  ActiveFilters? applied;
  await tester.binding.setSurfaceSize(const Size(500, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => FilterBottomSheet.show(
              context,
              currentFilters: current,
              availableGenres: const ['RPG', 'Platformer'],
              availableRegions: const ['USA'],
              availableLanguages: const ['En'],
              availableFranchises: const ['Zelda', 'Sonic'],
              availablePlayerCounts: const ['1', '2'],
              availableCollections: const [
                {'id': 7, 'name': 'Favorites'},
              ],
              onApply: (f) => applied = f,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return applied;
}

void main() {
  testWidgets('sort, franchise, players and collection reach the applied filters', (tester) async {
    ActiveFilters? applied;
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => FilterBottomSheet.show(
              context,
              currentFilters: const ActiveFilters(),
              availableGenres: const ['RPG'],
              availableRegions: const [],
              availableLanguages: const [],
              availableFranchises: const ['Zelda', 'Sonic'],
              availablePlayerCounts: const ['1', '2'],
              availableCollections: const [
                {'id': 7, 'name': 'Favorites'},
              ],
              onApply: (f) => applied = f,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await _reveal(tester, find.text('Favorites'));
    await tester.tap(find.text('Favorites'));
    await _reveal(tester, find.text('Rating'));
    await tester.tap(find.text('Rating'));
    await _reveal(tester, find.text('Zelda'));
    await tester.tap(find.text('Zelda'));
    await _reveal(tester, find.widgetWithText(FilterChip, '2'));
    await tester.tap(find.widgetWithText(FilterChip, '2'));
    await tester.pump();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();

    expect(applied, isNotNull);
    expect(applied!.sort, GameSort.rating);
    expect(applied!.sortDescending, isTrue); // best first by default
    expect(applied!.franchises, ['Zelda']);
    expect(applied!.playerCounts, ['2']);
    expect(applied!.collections, ['7']); // the id, not the name
  });

  testWidgets('Clear All resets sort and the new filters', (tester) async {
    await _openSheet(tester,
        current: const ActiveFilters(franchises: ['Zelda'], sort: GameSort.rating, sortDescending: true));
    await tester.tap(find.text('Clear All'));
    await tester.pump();
    await _reveal(tester, find.widgetWithText(FilterChip, 'Zelda'));
    final zelda = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Zelda'));
    expect(zelda.selected, isFalse);
    await _reveal(tester, find.widgetWithText(ChoiceChip, 'Name'));
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Name')).selected, isTrue);
  });

  testWidgets('saved filters load into the sheet and can be saved and deleted', (tester) async {
    ActiveFilters? applied;
    final saved = <String, ActiveFilters>{'Co-op RPGs': const ActiveFilters(genres: ['RPG'], playerCounts: ['2'])};
    final deleted = <String>[];
    String? savedName;
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => FilterBottomSheet.show(
              context,
              currentFilters: const ActiveFilters(),
              availableGenres: const ['RPG'],
              availableRegions: const [],
              availableLanguages: const [],
              availablePlayerCounts: const ['2'],
              availableCollections: const [],
              savedFilters: saved,
              onSaveFilter: (name, f) async => savedName = name,
              onDeleteSavedFilter: (name) async => deleted.add(name),
              onApply: (f) => applied = f,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Co-op RPGs'));
    await tester.pump();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(applied!.genres, ['RPG']);
    expect(applied!.playerCounts, ['2']);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Mine');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(savedName, 'Mine');
    expect(find.text('Mine'), findsOneWidget);

    await tester.tap(find.descendant(of: find.widgetWithText(InputChip, 'Mine'), matching: find.byTooltip('Delete')));
    await tester.pumpAndSettle();
    expect(deleted, ['Mine']);
    expect(find.text('Mine'), findsNothing);
  });
}
