import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/providers/library_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/ui/widgets/game_list_row.dart';
import 'package:freegosy/ui/widgets/layout_toggle_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

Game _game({int size = 3 * 1024 * 1024 * 1024, int rating = 0, String? status, DateTime? lastPlayed}) => Game(
      id: '1', name: 'Pokemon Emerald (USA)', platformDisplayName: 'Game Boy Advance',
      fileSize: size, userRating: rating, status: status, lastPlayed: lastPlayed,
    );

Widget _row(Game g, {bool downloaded = false, double width = 600}) => MaterialApp(
      home: Scaffold(body: SizedBox(width: width, child: GameListRow(game: g, isDownloaded: downloaded))),
    );

void main() {
  test('sizeLabel', () {
    expect(GameListRow.sizeLabel(0), '');
    expect(GameListRow.sizeLabel(512 * 1024), '512 KB');
    expect(GameListRow.sizeLabel(300 * 1024 * 1024), '300 MB');
    expect(GameListRow.sizeLabel((1.5 * 1024 * 1024 * 1024).round()), '1.5 GB');
  });

  test('agoLabel', () {
    final now = DateTime(2026, 10, 14, 12);
    expect(GameListRow.agoLabel(now.subtract(const Duration(hours: 5)), now: now), 'today');
    expect(GameListRow.agoLabel(now.subtract(const Duration(days: 1)), now: now), 'yesterday');
    expect(GameListRow.agoLabel(now.subtract(const Duration(days: 12)), now: now), '12d ago');
    expect(GameListRow.agoLabel(now.subtract(const Duration(days: 95)), now: now), '3mo ago');
    expect(GameListRow.agoLabel(now.subtract(const Duration(days: 800)), now: now), '2y ago');
  });

  testWidgets('shows title, platform, size, rating, status, last played and the downloaded check', (t) async {
    await t.pumpWidget(_row(_game(rating: 8, status: 'finished', lastPlayed: DateTime.now().subtract(const Duration(days: 3))), downloaded: true));
    expect(find.text(_game().displayName), findsOneWidget);
    expect(find.text('Game Boy Advance'), findsOneWidget);
    expect(find.text('3.0 GB'), findsOneWidget);
    expect(find.text('8/10'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('3d ago'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('leaves out what is unknown', (t) async {
    await t.pumpWidget(_row(_game(size: 0)));
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.flag_outlined), findsNothing);
    expect(find.byIcon(Icons.history), findsNothing);
    expect(find.byIcon(Icons.sd_storage_outlined), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a narrow window does not overflow', (t) async {
    await t.pumpWidget(_row(_game(rating: 8, status: 'completed_100', lastPlayed: DateTime.now()), downloaded: true, width: 300));
    expect(t.takeException(), isNull);
  });

  testWidgets('the toggle switches between grid and list and remembers it', (t) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(sp)]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: Scaffold(body: LayoutToggleButton()))));
    expect(container.read(libraryLayoutProvider), 'grid');
    expect(find.byIcon(Icons.view_list), findsOneWidget);
    await t.tap(find.byType(IconButton));
    await t.pump();
    expect(container.read(libraryLayoutProvider), 'list');
    expect(find.byIcon(Icons.grid_view), findsOneWidget);
    expect(sp.getString('library_layout'), 'list');
  });
}
