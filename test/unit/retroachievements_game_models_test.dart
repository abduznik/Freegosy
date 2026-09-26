import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/retroachievements/retroachievements_game_models.dart';
import 'package:freegosy/core/romm/romm_models.dart';

void main() {
  group('Game RetroAchievements fields', () {
    final rommJson = {
      'id': 42,
      'name': 'Sonic',
      'ra_id': 1,
      'merged_ra_metadata': {
        'achievements': [
          {'ra_id': 20, 'title': 'B', 'description': 'd', 'points': 10, 'badge_id': '2', 'display_order': 2, 'type': 'missable'},
          {'ra_id': 10, 'title': 'A', 'description': 'd', 'points': 5, 'badge_id': '1', 'display_order': 1, 'type': ''},
        ],
      },
    };

    test('parses ra_id and sorts merged_ra_metadata achievements', () {
      final game = Game.fromJson(rommJson);
      expect(game.raId, 1);
      expect(game.raAchievements.map((a) => a.id), [10, 20]);
      expect(game.raAchievements.first.type, isNull);
      expect(game.raAchievements.last.type, 'missable');
      expect(game.raAchievements.first.isUnlocked, isFalse);
    });

    test('survives a toJson/fromJson round-trip (offline cache)', () {
      final game = Game.fromJson(Game.fromJson(rommJson).toJson());
      expect(game.raId, 1);
      expect(game.raAchievements.map((a) => a.title), ['A', 'B']);
      expect(game.raAchievements.last.points, 10);
    });

    test('games without RA metadata have no raId or achievements', () {
      final game = Game.fromJson({'id': 1, 'name': 'x', 'merged_ra_metadata': null});
      expect(game.raId, isNull);
      expect(game.raAchievements, isEmpty);
    });
  });

  test('RetroAchievementsAward.parse maps HighestAwardKind', () {
    expect(RetroAchievementsAward.parse('mastered'), RetroAchievementsAward.mastered);
    expect(RetroAchievementsAward.parse('completed'), RetroAchievementsAward.completed);
    expect(RetroAchievementsAward.parse('beaten-softcore'), RetroAchievementsAward.beatenSoftcore);
    expect(RetroAchievementsAward.parse(null), isNull);
  });

  group('RetroAchievement', () {
    test('parses RA dates as UTC and ISO dates as-is', () {
      final a = RetroAchievement.fromJson({
        'ID': 1,
        'DateEarned': '2024-01-02 03:04:05',
        'DateEarnedHardcore': '2024-01-02T03:04:05+00:00',
      });
      expect(a.dateEarned, DateTime.utc(2024, 1, 2, 3, 4, 5));
      expect(a.dateEarnedHardcore, DateTime.utc(2024, 1, 2, 3, 4, 5));
      expect(a.isUnlockedHardcore, isTrue);
    });

    test('tolerates string numbers and missing fields', () {
      final a = RetroAchievement.fromJson({'ID': '7', 'Points': '25'});
      expect(a.id, 7);
      expect(a.points, 25);
      expect(a.title, '');
      expect(a.isUnlocked, isFalse);
    });

    test('softcore-only unlock is unlocked but not hardcore', () {
      final a = RetroAchievement.fromJson({'ID': 1, 'DateEarned': '2024-01-01 00:00:00'});
      expect(a.isUnlocked, isTrue);
      expect(a.isUnlockedHardcore, isFalse);
    });

    test('withUnlock keeps the definition and sets dates', () {
      const base = RetroAchievement(id: 3, title: 't', description: 'd', points: 10, badgeName: 'b', type: 'missable');
      final unlocked = base.withUnlock(earned: DateTime.utc(2024));
      expect(unlocked.title, 't');
      expect(unlocked.type, 'missable');
      expect(unlocked.isUnlocked, isTrue);
      expect(base.isUnlocked, isFalse);
    });

    test('sortAchievements breaks display-order ties by id', () {
      final sorted = sortAchievements(const [
        RetroAchievement(id: 9, title: '', description: '', points: 0, badgeName: '', displayOrder: 1),
        RetroAchievement(id: 2, title: '', description: '', points: 0, badgeName: '', displayOrder: 1),
        RetroAchievement(id: 5, title: '', description: '', points: 0, badgeName: '', displayOrder: 0),
      ]);
      expect(sorted.map((a) => a.id), [5, 2, 9]);
    });
  });

  group('RetroAchievementsGameProgress', () {
    test('fromJson leaves iconUrl null without ImageIcon', () {
      final p = RetroAchievementsGameProgress.fromJson({'ID': 1, 'Achievements': {}});
      expect(p.iconUrl, isNull);
      expect(p.totalCount, 0);
    });

    test('fromRomm merges earned_achievements into RomM\'s set', () {
      const set = [
        RetroAchievement(id: 1, title: 'a', description: '', points: 5, badgeName: '1'),
        RetroAchievement(id: 2, title: 'b', description: '', points: 10, badgeName: '2'),
        RetroAchievement(id: 3, title: 'c', description: '', points: 25, badgeName: '3'),
      ];
      final p = RetroAchievementsGameProgress.fromRomm(
        gameId: 99,
        achievements: set,
        progression: {
          'rom_ra_id': 99,
          'highest_award_kind': 'mastered',
          'earned_achievements': [
            {'id': '1', 'date': '2024-01-01 00:00:00', 'date_hardcore': '2024-01-01 00:00:00'},
            {'id': 3, 'date': '2024-02-01 00:00:00'},
            {'id': '404', 'date': '2024-02-01 00:00:00'}, // not in the set: ignored
          ],
        },
      );
      expect(p.gameId, 99);
      expect(p.unlockedCount, 2);
      expect(p.unlockedHardcoreCount, 1);
      expect(p.earnedPoints, 30);
      expect(p.totalPoints, 40);
      expect(p.highestAward, RetroAchievementsAward.mastered);
      expect(p.achievements.map((a) => a.id), [1, 2, 3]);
    });

    test('fromRomm with no earned achievements', () {
      final p = RetroAchievementsGameProgress.fromRomm(
        gameId: 1,
        achievements: const [RetroAchievement(id: 1, title: '', description: '', points: 1, badgeName: '')],
        progression: {'rom_ra_id': 1},
      );
      expect(p.unlockedCount, 0);
      expect(p.highestAward, isNull);
    });
  });

  test('RetroAchievementsAward.parse ignores unknown kinds', () {
    expect(RetroAchievementsAward.parse('beaten-hardcore'), RetroAchievementsAward.beatenHardcore);
    expect(RetroAchievementsAward.parse('participated'), isNull);
  });
}
