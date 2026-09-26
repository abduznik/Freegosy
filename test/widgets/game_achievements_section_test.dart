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
}
