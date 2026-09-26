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
}
