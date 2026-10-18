import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/discover.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/stats/play_time_store.dart';
import 'package:freegosy/providers/paginated_games_provider.dart';

import '../helpers/fake_retroachievements.dart';

void main() {
  group('GameSort.parse', () {
    test('accepts names and RomM fields, ignoring case and separators', () {
      expect(GameSort.parse('rating'), GameSort.rating);
      expect(GameSort.parse('Release-Date'), GameSort.releaseDate);
      expect(GameSort.parse('first_release_date'), GameSort.releaseDate);
      expect(GameSort.parse('last_played'), GameSort.lastPlayed);
      expect(GameSort.parse('added'), GameSort.recentlyAdded); // CLI aliases
      expect(GameSort.parse('release'), GameSort.releaseDate);
      expect(GameSort.parse('played'), GameSort.lastPlayed);
      expect(GameSort.parse('nope'), isNull);
      expect(GameSort.parse(null), isNull);
    });
  });

  group('DiscoverPreset.parse', () {
    test('matches CLI names and enum names', () {
      expect(DiscoverPreset.parse('top-unplayed'), DiscoverPreset.topUnplayed);
      expect(DiscoverPreset.parse('most-played'), DiscoverPreset.mostPlayed);
      expect(DiscoverPreset.parse('recentlyAdded'), DiscoverPreset.recentlyAdded);
      expect(DiscoverPreset.parse('x'), isNull);
    });
  });

  test('mostPlayedGameIds orders by total time and drops unplayed games', () async {
    final store = PlayTimeStore(InMemoryAppPreferences());
    final t = DateTime(2026, 1, 1);
    await store.record('a', t, t.add(const Duration(minutes: 5)));
    await store.record('b', t, t.add(const Duration(hours: 2)));
    await store.record('c', t, t.add(const Duration(seconds: 3))); // too short, not counted
    expect(mostPlayedGameIds(store), ['b', 'a']);
    expect(mostPlayedGameIds(store, limit: 1), ['b']);
  });

  test('Game reads franchises and player count from metadata', () {
    final game = Game.fromJson({
      'id': 1,
      'name': 'Sonic',
      'metadatum': {'franchises': ['Sonic', 'Sega'], 'player_count': '1-2'},
    });
    expect(game.franchises, ['Sonic', 'Sega']);
    expect(game.playerCount, '1-2');
    expect(Game.fromJson(game.toJson()).franchises, ['Sonic', 'Sega']);
  });

  test('ActiveFilters counts a non-default sort or franchise as active', () {
    expect(const ActiveFilters().hasActiveFilters, isFalse);
    expect(const ActiveFilters(sort: GameSort.rating).hasActiveFilters, isTrue);
    expect(const ActiveFilters(franchises: ['Zelda']).hasActiveFilters, isTrue);
    expect(const ActiveFilters(playerCounts: ['2']).hasActiveFilters, isTrue);
  });
}
