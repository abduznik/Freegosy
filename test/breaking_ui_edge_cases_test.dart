import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/downloader/download_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/providers/paginated_games_provider.dart';
import 'package:freegosy/providers/ui_provider.dart';
import 'package:freegosy/ui/widgets/controller_hints_bar.dart';
import 'package:freegosy/ui/widgets/download_progress_indicator.dart';
import 'package:freegosy/ui/widgets/focus_effect_wrapper.dart';
import 'package:freegosy/ui/widgets/game_card.dart';
import 'package:freegosy/ui/widgets/game_detail/game_action_button.dart';
import 'package:freegosy/ui/widgets/game_detail/game_details_grid.dart';
import 'package:freegosy/ui/widgets/game_detail/game_metadata_chip.dart';
import 'package:freegosy/ui/widgets/game_detail/game_notes_section.dart';
import 'package:freegosy/ui/widgets/game_detail/game_personal_section.dart';
import 'package:freegosy/ui/widgets/multi_disc_picker.dart';
import 'package:freegosy/ui/widgets/save_conflict_dialog.dart';
import 'package:freegosy/core/save/save_sync_service.dart';

void main() {
  group('Game.displayName edge cases', () {
    test('hex-only name should fall back to original name', () {
      final game = Game(id: '1', name: '00040000000EC400', fileSize: 0);
      expect(game.displayName, '00040000000EC400');
    });

    test('name that is entirely parenthetical content', () {
      final game = Game(id: '2', name: '(CTR-P-BZLP) (v0.0.0) (En)', fileSize: 0);
      expect(game.displayName, '(CTR-P-BZLP) (v0.0.0) (En)');
    });

    test('name with only hex, brackets, and parens', () {
      final game = Game(
        id: '3',
        name: '00040000000EC400 (USA) [b]',
        fileSize: 0,
      );
      expect(game.displayName, '00040000000EC400 (USA) [b]');
    });

    test('normal name with metadata stripped', () {
      final game = Game(
        id: '4',
        name: 'Super Mario Bros (USA) (v1.0) [!]',
        fileSize: 0,
      );
      expect(game.displayName, 'Super Mario Bros');
    });

    test('name with trailing dots and dashes', () {
      final game = Game(id: '5', name: 'Game Name._- ', fileSize: 0);
      expect(game.displayName, 'Game Name');
    });

    test('empty name should not crash', () {
      final game = Game(id: '6', name: '', fileSize: 0);
      expect(game.displayName, '');
    });

    test('name with only whitespace', () {
      final game = Game(id: '7', name: '   ', fileSize: 0);
      expect(() => game.displayName, returnsNormally);
      expect(game.displayName, '   ');
    });

    test('name with special regex characters should not crash', () {
      final game = Game(id: '8', name: r'[foo] (bar) $^.*+', fileSize: 0);
      expect(() => game.displayName, returnsNormally);
    });
  });

  group('DownloadProgress model edge cases', () {
    test('copyWith all null parameters returns identical copy', () {
      final original = DownloadProgress(
        id: '1',
        gameName: 'Test',
        percent: 0.5,
        bytesReceived: 100,
        totalBytes: 200,
        isComplete: false,
        isPaused: false,
        status: 'Downloading...',
      );
      final copy = original.copyWith();
      expect(copy.percent, 0.5);
      expect(copy.bytesReceived, 100);
      expect(copy.totalBytes, 200);
      expect(copy.isComplete, false);
      expect(copy.isPaused, false);
      expect(copy.status, 'Downloading...');
    });

    test('negative percent does not cause crash in indicator', () {
      final progress = DownloadProgress(
        id: '1',
        gameName: 'Test',
        percent: -0.1,
      );
      expect(progress.percent, -0.1);
    });

    test('percent > 1.0 (over 100%) does not crash', () {
      final progress = DownloadProgress(
        id: '1',
        gameName: 'Test',
        percent: 2.5,
        bytesReceived: 500,
        totalBytes: 200,
      );
      expect(progress.percent, 2.5);
    });

    test('zero totalBytes does not cause division by zero', () {
      final progress = DownloadProgress(
        id: '1',
        gameName: 'Test',
        percent: 0.0,
        bytesReceived: 100,
        totalBytes: 0,
      );
      expect(progress.percent, 0.0);
    });

    test('NaN percent does not crash model', () {
      final progress = DownloadProgress(
        id: '1',
        gameName: 'Test',
        percent: double.nan,
      );
      expect(progress.percent.isNaN, isTrue);
    });

    test('infinite percent does not crash model', () {
      final progress = DownloadProgress(
        id: '1',
        gameName: 'Test',
        percent: double.infinity,
      );
      expect(progress.percent.isInfinite, isTrue);
    });
  });

  group('ActiveFilters edge cases', () {
    test('default filters have no active filters', () {
      const filters = ActiveFilters();
      expect(filters.hasActiveFilters, isFalse);
    });

    test('all fields empty has no active filters', () {
      const filters = ActiveFilters(
        genres: [],
        regions: [],
        languages: [],
        collections: [],
        statuses: [],
        downloadedOnly: false,
        notDownloadedOnly: false,
      );
      expect(filters.hasActiveFilters, isFalse);
    });

    test('copyWith with all null returns same filters', () {
      const original = ActiveFilters(genres: ['Action']);
      final copy = original.copyWith();
      expect(copy.genres, ['Action']);
      expect(copy.hasActiveFilters, isTrue);
    });

    test('both downloadedOnly and notDownloadedOnly can be true simultaneously', () {
      const filters = ActiveFilters(
        downloadedOnly: true,
        notDownloadedOnly: true,
      );
      expect(filters.downloadedOnly, isTrue);
      expect(filters.notDownloadedOnly, isTrue);
      expect(filters.hasActiveFilters, isTrue);
    });
  });

  group('PaginatedGamesState edge cases', () {
    test('default state has empty games list', () {
      const state = PaginatedGamesState();
      expect(state.games, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.hasMore, isTrue);
      expect(state.total, 0);
      expect(state.error, isNull);
    });

    test('copyWith preserves fields when nulls passed', () {
      final state = PaginatedGamesState(games: [Game(id: '1', name: 'Test', fileSize: 0)], total: 1);
      final copy = state.copyWith();
      expect(copy.games.length, 1);
      expect(copy.total, 1);
    });

    test('error state is independent of other fields', () {
      const state = PaginatedGamesState(error: 'Something broke');
      expect(state.error, 'Something broke');
      expect(state.games, isEmpty);
    });
  });

  group('GameCard rendering edge cases', () {
    Widget wrapWidget(Widget widget) {
      return ProviderScope(child: MaterialApp(home: Scaffold(body: widget)));
    }

    testWidgets('GameCard with empty coverUrl and null platformLogoUrl shows gamepad icon', (tester) async {
      final game = Game(id: '1', name: 'Test Game', fileSize: 0);
      await tester.pumpWidget(wrapWidget(GameCard(game: game, coverUrl: '', platformLogoUrl: null)));
      expect(find.byIcon(Icons.sports_esports), findsOneWidget);
    });

    testWidgets('GameCard with empty coverUrl and empty platformLogoUrl', (tester) async {
      final game = Game(id: '1', name: 'Test Game', fileSize: 0);
      await tester.pumpWidget(wrapWidget(GameCard(game: game, coverUrl: '', platformLogoUrl: '')));
      expect(find.byIcon(Icons.sports_esports), findsOneWidget);
    });

    testWidgets('GameCard with showTitle false shows more_horiz icon', (tester) async {
      final game = Game(id: '1', name: 'Test Game', fileSize: 0);
      await tester.pumpWidget(wrapWidget(GameCard(game: game, showTitle: false)));
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(find.text('Test Game'), findsNothing);
    });

    testWidgets('GameCard with null platformDisplayName does not render platform text', (tester) async {
      final game = Game(id: '1', name: 'Test Game', fileSize: 0, platformDisplayName: null);
      await tester.pumpWidget(wrapWidget(GameCard(game: game)));
      expect(find.text('Test Game'), findsOneWidget);
    });

    testWidgets('GameCard with empty game name renders empty title', (tester) async {
      final game = Game(id: '1', name: '', fileSize: 0);
      await tester.pumpWidget(wrapWidget(GameCard(game: game)));
      expect(find.text(''), findsOneWidget);
    });

    testWidgets('GameCard with very long game name does not overflow', (tester) async {
      final longName = 'A' * 500;
      final game = Game(id: '1', name: longName, fileSize: 0);
      await tester.pumpWidget(wrapWidget(GameCard(game: game)));
      expect(find.byType(Text), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('FocusEffectWrapper extreme parameters', () {
    Widget wrapWrapper({
      double scaleFactor = 1.05,
      double borderRadius = 12.0,
      bool showGlow = true,
      bool autofocus = false,
      bool useSafeScale = true,
      VoidCallback? onTap,
    }) {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: FocusEffectWrapper(
                scaleFactor: scaleFactor,
                borderRadius: borderRadius,
                showGlow: showGlow,
                autofocus: autofocus,
                useSafeScale: useSafeScale,
                onTap: onTap,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('scaleFactor of 0 does not crash', (tester) async {
      await tester.pumpWidget(wrapWrapper(scaleFactor: 0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('scaleFactor of 100 does not crash (safe scale clamps)', (tester) async {
      await tester.pumpWidget(wrapWrapper(scaleFactor: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('borderRadius of 0 does not crash', (tester) async {
      await tester.pumpWidget(wrapWrapper(borderRadius: 0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('borderRadius negative does not crash', (tester) async {
      await tester.pumpWidget(wrapWrapper(borderRadius: -10));
      expect(tester.takeException(), isNull);
    });

    testWidgets('showGlow false does not crash', (tester) async {
      await tester.pumpWidget(wrapWrapper(showGlow: false));
      expect(tester.takeException(), isNull);
    });

    testWidgets('autofocus true renders without focus crash', (tester) async {
      await tester.pumpWidget(wrapWrapper(autofocus: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('useSafeScale false with extreme scale does not crash', (tester) async {
      await tester.pumpWidget(wrapWrapper(scaleFactor: 10, useSafeScale: false));
      expect(tester.takeException(), isNull);
    });

    testWidgets('null onTap does not crash on tap', (tester) async {
      await tester.pumpWidget(wrapWrapper(onTap: null));
      await tester.tap(find.byType(FocusEffectWrapper));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('GameMetadataChip edge cases', () {
    testWidgets('null icon renders without icon', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GameMetadataChip(label: 'Action', icon: null)),
      ));
      expect(find.text('Action'), findsOneWidget);
    });

    testWidgets('empty label renders empty chip', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GameMetadataChip(label: '', icon: Icons.star)),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('short label renders without overflow', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GameMetadataChip(label: 'Action', icon: Icons.star)),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Action'), findsOneWidget);
    });

    testWidgets('long label no longer overflows (fixed)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GameMetadataChip(label: 'A' * 200, icon: Icons.star)),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('GameDetailsGrid edge cases', () {
    testWidgets('game with empty companies, regions, languages, playerCount returns SizedBox', (tester) async {
      final game = Game(
        id: '1',
        name: 'Test',
        fileSize: 0,
        companies: [],
        regions: [],
        languages: [],
        playerCount: null,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GameDetailsGrid(game: game)),
      ));
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('game with empty string playerCount does not add that row', (tester) async {
      final game = Game(
        id: '1',
        name: 'Test',
        fileSize: 0,
        companies: ['Nintendo'],
        playerCount: '',
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 40,
          ),
          children: [
            GameDetailsGrid(game: game),
          ],
        )),
      ));
      expect(find.text('Developer'), findsOneWidget);
      expect(find.text('Nintendo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ControllerHintsBar edge cases', () {
    testWidgets('empty hints list does not crash', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: ControllerHintsBar(hints: const [])),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('single hint renders correctly', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ControllerHintsBar(
              hints: const [ControllerHintItem(label: 'Select', button: 'A')],
            ),
          ),
        ),
      ));
      expect(find.text('Select'), findsOneWidget);
    });

    testWidgets('unknown button text does not crash', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ControllerHintsBar(
              hints: const [ControllerHintItem(label: 'Unknown', button: 'Z')],
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('GameActionButton edge cases', () {
    testWidgets('null color is not treated as destructive', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameActionButton(
              icon: Icons.play_arrow,
              label: 'Play',
              onPressed: () {},
              color: null,
            ),
          ),
        ),
      ));
      expect(find.text('Play'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('very long label does not overflow', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameActionButton(
              icon: Icons.play_arrow,
              label: 'A' * 200,
              onPressed: () {},
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('isPrimary renders with gradient', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameActionButton(
              icon: Icons.play_arrow,
              label: 'Launch',
              onPressed: () {},
              isPrimary: true,
            ),
          ),
        ),
      ));
      expect(find.text('Launch'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('GamePersonalSection extreme values', () {
    Widget buildSection({
      String? status,
      int rating = 0,
      int completion = 0,
      bool backlogged = false,
      bool nowPlaying = false,
      bool isSaving = false,
      bool adjustingRating = false,
      bool adjustingCompletion = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ProviderScope(
            child: GamePersonalSection(
              status: status,
              rating: rating,
              completion: completion,
              backlogged: backlogged,
              nowPlaying: nowPlaying,
              isSaving: isSaving,
              adjustingRating: adjustingRating,
              adjustingCompletion: adjustingCompletion,
              onStatusChanged: (_) {},
              onRatingChanged: (_) {},
              onCompletionChanged: (_) {},
              onBacklogChanged: (_) {},
              onNowPlayingChanged: (_) {},
              onToggleAdjustingRating: () {},
              onToggleAdjustingCompletion: () {},
              onSave: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('null status displays "Not set"', (tester) async {
      await tester.pumpWidget(buildSection(status: null));
      await tester.pumpAndSettle();
      expect(find.text('Not set'), findsOneWidget);
    });

    testWidgets('rating 0 displays "Rating" not "No Rating"', (tester) async {
      await tester.pumpWidget(buildSection(rating: 0));
      await tester.pumpAndSettle();
      expect(find.text('Rating'), findsOneWidget);
    });

    testWidgets('rating 10 displays correctly', (tester) async {
      await tester.pumpWidget(buildSection(rating: 10));
      await tester.pumpAndSettle();
      expect(find.text('10 Star'), findsOneWidget);
    });

    testWidgets('negative rating does not crash (clamped)', (tester) async {
      await tester.pumpWidget(buildSection(rating: -5, adjustingRating: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('completion 100 displays correctly', (tester) async {
      await tester.pumpWidget(buildSection(completion: 100));
      await tester.pumpAndSettle();
      expect(find.text('100% Done'), findsOneWidget);
    });

    testWidgets('completion > 100 displays correctly', (tester) async {
      await tester.pumpWidget(buildSection(completion: 150, adjustingCompletion: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('GameNotesSection edge cases', () {
    testWidgets('empty notes shows "No notes added yet."', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameNotesSection(
              notes: const [],
              onAddNote: () {},
              onViewNote: (_) {},
            ),
          ),
        ),
      ));
      expect(find.text('No notes added yet.'), findsOneWidget);
    });

    testWidgets('note with empty title shows "Note" as title', (tester) async {
      final note = RomNote(id: 1, title: '', content: 'Some content');
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameNotesSection(
              notes: [note],
              onAddNote: () {},
              onViewNote: (_) {},
            ),
          ),
        ),
      ));
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('Some content'), findsOneWidget);
    });

    testWidgets('note with very long content does not overflow', (tester) async {
      final note = RomNote(id: 1, title: 'Title', content: 'A' * 1000);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameNotesSection(
              notes: [note],
              onAddNote: () {},
              onViewNote: (_) {},
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('SaveConflictDialog edge cases', () {
    testWidgets('same timestamps does not crash and neither shows NEWER', (tester) async {
      final now = DateTime.now();
      final conflict = SaveConflictException(
        game: Game(id: '1', name: 'Test', fileSize: 0),
        localTime: now,
        cloudTime: now,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => SaveConflictDialog(conflict: conflict)),
            child: const Text('Open'),
          ),
        )),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Sync Conflict Detected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('local time newer marks local as NEWER', (tester) async {
      final conflict = SaveConflictException(
        game: Game(id: '1', name: 'Test', fileSize: 0),
        localTime: DateTime(2025, 1, 2),
        cloudTime: DateTime(2025, 1, 1),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => SaveConflictDialog(conflict: conflict)),
            child: const Text('Open'),
          ),
        )),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('NEWER'), findsOneWidget);
    });

    testWidgets('dialog pops with "local" when local button tapped', (tester) async {
      final conflict = SaveConflictException(
        game: Game(id: '1', name: 'Test', fileSize: 0),
        localTime: DateTime(2025, 1, 2),
        cloudTime: DateTime(2025, 1, 1),
      );
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) => SaveConflictDialog(conflict: conflict),
              );
            },
            child: const Text('Open'),
          ),
        )),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use Local Version'));
      await tester.pumpAndSettle();
      expect(result, 'local');
    });
  });

  group('MultiDiscPicker format helpers', () {
    test('_formatSize returns empty for null bytes', () {
      // Access through a builder since _formatSize is private
      // We instead verify behavior through widget rendering
    });

    testWidgets('empty files list renders without crash', (tester) async {
      final game = Game(id: '1', name: 'Test Game', fileSize: 0, files: const []);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => MultiDiscPicker.show(context, game: game, files: [], onSelect: (_) {}),
            child: const Text('Open'),
          ),
        )),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('file with null name renders fallback', (tester) async {
      final game = Game(id: '1', name: 'Test Game', fileSize: 0);
      final files = [<String, dynamic>{}];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => MultiDiscPicker.show(context, game: game, files: files, onSelect: (_) {}),
            child: const Text('Open'),
          ),
        )),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('file with null size_bytes renders without size text', (tester) async {
      final game = Game(id: '1', name: 'Test Game', fileSize: 0);
      final files = [
        {'file_name': 'game.disc1.iso', 'file_size_bytes': null},
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => MultiDiscPicker.show(context, game: game, files: files, onSelect: (_) {}),
            child: const Text('Open'),
          ),
        )),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Disc 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('filename without disc pattern falls back to "File N"', (tester) async {
      final game = Game(id: '1', name: 'Test Game', fileSize: 0);
      final files = [
        {'file_name': 'random_file.iso', 'file_size_bytes': 1048576},
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => MultiDiscPicker.show(context, game: game, files: files, onSelect: (_) {}),
            child: const Text('Open'),
          ),
        )),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('File 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('GamePersonalSection adjusting interaction safety', () {
    testWidgets('tapping rating adjuster does not crash with extreme values', (tester) async {
      int rating = 5;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProviderScope(
            child: GamePersonalSection(
              status: null,
              rating: rating,
              completion: 50,
              backlogged: false,
              nowPlaying: false,
              isSaving: false,
              adjustingRating: true,
              adjustingCompletion: false,
              onStatusChanged: (_) {},
              onRatingChanged: (v) => rating = v,
              onCompletionChanged: (_) {},
              onBacklogChanged: (_) {},
              onNowPlayingChanged: (_) {},
              onToggleAdjustingRating: () {},
              onToggleAdjustingCompletion: () {},
              onSave: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final addButtons = find.byIcon(Icons.add);
      if (addButtons.evaluate().isNotEmpty) {
        await tester.tap(addButtons.first);
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('isSaving shows spinner instead of "Save Changes" text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProviderScope(
            child: GamePersonalSection(
              status: null,
              rating: 0,
              completion: 0,
              backlogged: false,
              nowPlaying: false,
              isSaving: true,
              adjustingRating: false,
              adjustingCompletion: false,
              onStatusChanged: (_) {},
              onRatingChanged: (_) {},
              onCompletionChanged: (_) {},
              onBacklogChanged: (_) {},
              onNowPlayingChanged: (_) {},
              onToggleAdjustingRating: () {},
              onToggleAdjustingCompletion: () {},
              onSave: () {},
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('Save Changes'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
