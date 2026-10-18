import '../stats/play_time_store.dart';

/// How a game list is ordered. [apiField] is RomM's `order_by` value.
enum GameSort {
  name('name', 'Name', false),
  recentlyAdded('id', 'Recently added', true),
  releaseDate('first_release_date', 'Release date', true),
  rating('average_rating', 'Rating', true),
  lastPlayed('last_played', 'Last played', true);

  const GameSort(this.apiField, this.label, this.newestFirst);
  final String apiField;
  final String label;

  /// True when the natural reading of this sort is descending (newest, best).
  final bool newestFirst;

  static GameSort? parse(String? value) {
    if (value == null) return null;
    final v = value.toLowerCase().replaceAll(RegExp(r'[-_ ]'), '');
    for (final s in GameSort.values) {
      if (s.name.toLowerCase() == v || s.apiField.replaceAll('_', '') == v) return s;
    }
    return null;
  }
}

/// Ready-made lists in the Discover bundle. Most are a RomM query; [mostPlayed]
/// comes from the play time Freegosy measures on this computer.
enum DiscoverPreset {
  recentlyAdded('recent', 'Recently Added'),
  recentlyPlayed('continue', 'Continue Playing'),
  topUnplayed('top-unplayed', 'Top Unplayed'),
  topRated('top-rated', 'Top Rated'),
  mostPlayed('most-played', 'Most Played');

  const DiscoverPreset(this.cliName, this.title);
  final String cliName;
  final String title;

  static DiscoverPreset? parse(String? value) {
    if (value == null) return null;
    final v = value.toLowerCase();
    for (final p in DiscoverPreset.values) {
      if (p.cliName == v || p.name.toLowerCase() == v.replaceAll('-', '')) return p;
    }
    return null;
  }

  static String get cliNames => DiscoverPreset.values.map((p) => p.cliName).join(', ');
}

/// Game ids ordered by how long they were played on this computer, longest
/// first. Games with no recorded time are left out.
List<String> mostPlayedGameIds(PlayTimeStore store, {int limit = 15}) {
  final all = store.allStats().entries.where((e) => e.value.total > Duration.zero).toList()
    ..sort((a, b) => b.value.total.compareTo(a.value.total));
  return all.take(limit).map((e) => e.key).toList();
}
