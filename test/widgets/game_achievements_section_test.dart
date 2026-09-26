import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/retroachievements/retroachievements_game_models.dart';
import 'package:freegosy/core/retroachievements/retroachievements_models.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/providers/retroachievements_provider.dart';
import 'package:freegosy/ui/widgets/game_detail/game_achievements_section.dart';

const _a1 = RetroAchievement(id: 1, title: 'First', description: 'd', points: 5, badgeName: '1', displayOrder: 1);
const _a2 = RetroAchievement(id: 2, title: 'Second', description: 'd', points: 10, badgeName: '2', displayOrder: 2);

Widget _wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

void main() {
  testWidgets('renders nothing for games RomM did not match to RetroAchievements', (tester) async {
    await tester.pumpWidget(_wrap(GameAchievementsSection(game: Game(id: '1', name: 'x', fileSize: 0)), [
      rommRetroAchievementsProgressionProvider.overrideWith((ref) => Future.value({})),
      retroAchievementsCredentialsProvider.overrideWith((ref) => Future.value(null)),
    ]));
    expect(find.text('Achievements'), findsNothing);
  });

  testWidgets('without an RA account shows the RomM achievement set and a connect hint', (tester) async {
    final game = Game(id: '1', name: 'x', fileSize: 0, raId: 7, raAchievements: const [_a1, _a2]);
    await tester.pumpWidget(_wrap(GameAchievementsSection(game: game), [
      retroAchievementsCredentialsProvider.overrideWith((ref) => Future.value(null)),
      rommRetroAchievementsProgressionProvider.overrideWith((ref) => Future.value({})),
    ]));
    await tester.pump();

    expect(find.text('Achievements'), findsOneWidget);
    expect(find.text('2 achievements · 15 points'), findsOneWidget);
    expect(find.textContaining('Connect your RetroAchievements account'), findsOneWidget);
  });

  testWidgets('with an RA account shows unlock progress and the award', (tester) async {
    final game = Game(id: '1', name: 'x', fileSize: 0, raId: 7);
    final progress = RetroAchievementsGameProgress(
      gameId: 7,
      title: 'x',
      consoleName: 'y',
      highestAward: RetroAchievementsAward.mastered,
      achievements: [
        RetroAchievement(
          id: 1, title: 'First', description: 'd', points: 5, badgeName: '1',
          dateEarned: DateTime.utc(2024), dateEarnedHardcore: DateTime.utc(2024),
        ),
        _a2,
      ],
    );
    await tester.pumpWidget(_wrap(GameAchievementsSection(game: game), [
      retroAchievementsCredentialsProvider.overrideWith(
        (ref) => Future.value(const RetroAchievementsCredentials(username: 'u', webApiKey: 'k')),
      ),
      retroAchievementsGameProgressProvider(7).overrideWith((ref) => Future.value(progress)),
    ]));
    await tester.pump();
    await tester.pump();

    expect(find.text('Mastered'), findsOneWidget);
    expect(find.text('1 / 2 unlocked · 5 / 15 points · 1 hardcore'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('without a Web API key uses the progress RomM synced', (tester) async {
    final game = Game(id: '1', name: 'x', fileSize: 0, raId: 7, raAchievements: const [_a1, _a2]);
    await tester.pumpWidget(_wrap(GameAchievementsSection(game: game), [
      retroAchievementsCredentialsProvider.overrideWith(
        (ref) => Future.value(const RetroAchievementsCredentials(username: 'u', webApiKey: '')),
      ),
      rommRetroAchievementsProgressionProvider.overrideWith((ref) => Future.value({
            7: {
              'rom_ra_id': 7,
              'highest_award_kind': 'beaten-softcore',
              'earned_achievements': [
                {'id': '2', 'date': '2024-05-01 10:00:00'},
              ],
            },
          })),
    ]));
    await tester.pump();
    await tester.pump();

    expect(find.text('Beaten (softcore)'), findsOneWidget);
    expect(find.text('1 / 2 unlocked · 10 / 15 points'), findsOneWidget);
    expect(find.text('Progress as last synced by RomM.'), findsOneWidget);
  });

  group('interactions', () {
    final unlockedHardcore = RetroAchievement(
      id: 1, title: 'First', description: 'Beat the first boss', points: 5, badgeName: '111',
      type: 'progression', numAwarded: 1200, numAwardedHardcore: 300,
      dateEarned: DateTime.utc(2024, 3, 10, 12), dateEarnedHardcore: DateTime.utc(2024, 3, 10, 12),
    );
    const locked = RetroAchievement(id: 2, title: 'Second', description: 'Find the secret', points: 10, badgeName: '222');

    List<Override> connected(RetroAchievementsGameProgress progress) => [
          retroAchievementsCredentialsProvider.overrideWith(
            (ref) => Future.value(const RetroAchievementsCredentials(username: 'u', webApiKey: 'k')),
          ),
          retroAchievementsGameProgressProvider(7).overrideWith((ref) => Future.value(progress)),
        ];

    RetroAchievementsGameProgress progressOf(List<RetroAchievement> list) =>
        RetroAchievementsGameProgress(gameId: 7, title: '', consoleName: '', achievements: list);

    Iterable<String> badgeUrls(WidgetTester tester) =>
        tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).map((i) => i.imageUrl);

    testWidgets('locked badges use the greyed-out image, unlocked the colour one', (tester) async {
      await tester.pumpWidget(_wrap(
        GameAchievementsSection(game: Game(id: '1', name: 'x', fileSize: 0, raId: 7)),
        connected(progressOf([unlockedHardcore, locked])),
      ));
      await tester.pump();
      await tester.pump();

      expect(badgeUrls(tester), [
        'https://media.retroachievements.org/Badge/111.png',
        'https://media.retroachievements.org/Badge/222_lock.png',
      ]);
    });

    testWidgets('without unlock data every badge shows in colour', (tester) async {
      await tester.pumpWidget(_wrap(
        GameAchievementsSection(game: Game(id: '1', name: 'x', fileSize: 0, raId: 7, raAchievements: const [locked])),
        [
          retroAchievementsCredentialsProvider.overrideWith((ref) => Future.value(null)),
          rommRetroAchievementsProgressionProvider.overrideWith((ref) => Future.value({})),
        ],
      ));
      await tester.pump();

      expect(badgeUrls(tester), ['https://media.retroachievements.org/Badge/222.png']);
    });

    testWidgets('tapping an unlocked badge shows its details', (tester) async {
      await tester.pumpWidget(_wrap(
        GameAchievementsSection(game: Game(id: '1', name: 'x', fileSize: 0, raId: 7)),
        connected(progressOf([unlockedHardcore, locked])),
      ));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('First'));
      await tester.pumpAndSettle();

      expect(find.text('Beat the first boss'), findsOneWidget);
      expect(find.text('5 points · Progression'), findsOneWidget);
      expect(find.text('Unlocked by 1200 players (300 hardcore)'), findsOneWidget);
      expect(find.textContaining('Unlocked in hardcore on 2024-03-'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Beat the first boss'), findsNothing);
    });

    testWidgets('tapping a locked badge says Locked', (tester) async {
      await tester.pumpWidget(_wrap(
        GameAchievementsSection(game: Game(id: '1', name: 'x', fileSize: 0, raId: 7)),
        connected(progressOf([unlockedHardcore, locked])),
      ));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('Second'));
      await tester.pumpAndSettle();

      expect(find.text('Find the secret'), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
    });

    testWidgets('a game with an empty set says so', (tester) async {
      await tester.pumpWidget(_wrap(
        GameAchievementsSection(game: Game(id: '1', name: 'x', fileSize: 0, raId: 7)),
        connected(progressOf(const [])),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('This game has no achievements yet.'), findsOneWidget);
    });

    testWidgets('a rejected Web API key falls back to RomM\'s set with a hint', (tester) async {
      await tester.pumpWidget(_wrap(
        GameAchievementsSection(game: Game(id: '1', name: 'x', fileSize: 0, raId: 7, raAchievements: const [locked])),
        [
          retroAchievementsCredentialsProvider.overrideWith(
            (ref) => Future.value(const RetroAchievementsCredentials(username: 'u', webApiKey: 'bad')),
          ),
          retroAchievementsGameProgressProvider(7).overrideWith(
            (ref) => Future<RetroAchievementsGameProgress?>.error(const RetroAchievementsAuthException('nope')),
          ),
        ],
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('RetroAchievements rejected your Web API key — update it in Settings.'), findsOneWidget);
      expect(find.byTooltip('Second'), findsOneWidget);
    });

    testWidgets('a network error falls back with a generic message', (tester) async {
      await tester.pumpWidget(_wrap(
        GameAchievementsSection(game: Game(id: '1', name: 'x', fileSize: 0, raId: 7, raAchievements: const [locked])),
        [
          retroAchievementsCredentialsProvider.overrideWith(
            (ref) => Future.value(const RetroAchievementsCredentials(username: 'u', webApiKey: 'k')),
          ),
          retroAchievementsGameProgressProvider(7).overrideWith(
            (ref) => Future<RetroAchievementsGameProgress?>.error(Exception('offline')),
          ),
        ],
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not load your RetroAchievements progress.'), findsOneWidget);
    });

    testWidgets('an account without a Web API key and no RomM progress hints to add the key', (tester) async {
      await tester.pumpWidget(_wrap(
        GameAchievementsSection(game: Game(id: '1', name: 'x', fileSize: 0, raId: 7, raAchievements: const [locked])),
        [
          retroAchievementsCredentialsProvider.overrideWith(
            (ref) => Future.value(const RetroAchievementsCredentials(username: 'u', webApiKey: '')),
          ),
          rommRetroAchievementsProgressionProvider.overrideWith((ref) => Future.value({})),
        ],
      ));
      await tester.pump();

      expect(find.text('Add your Web API key in Settings → RetroAchievements to see your unlocks.'), findsOneWidget);
    });
  });
}
