import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/active_filters.dart';
import 'package:freegosy/core/romm/discover.dart';
import 'package:freegosy/core/romm/saved_filters.dart';

import '../helpers/fake_retroachievements.dart';

void main() {
  late SavedFilterStore store;
  setUp(() => store = SavedFilterStore(InMemoryAppPreferences()));

  test('starts empty', () => expect(store.all(), isEmpty));

  test('round-trips every field', () async {
    const filters = ActiveFilters(
      genres: ['RPG'],
      regions: ['USA'],
      languages: ['En'],
      collections: ['7'],
      statuses: ['backlogged'],
      franchises: ['Zelda'],
      playerCounts: ['2'],
      sort: GameSort.rating,
      sortDescending: true,
      downloadedOnly: true,
    );
    await store.save('Co-op', filters);
    final back = store.find('co-OP')!;
    expect(back.toJson(), filters.toJson());
    expect(back.sort, GameSort.rating);
    expect(back.downloadedOnly, isTrue);
  });

  test('saving under an existing name (any case) replaces it', () async {
    await store.save('Mine', const ActiveFilters(genres: ['A']));
    await store.save('mine', const ActiveFilters(genres: ['B']));
    expect(store.all().keys, ['mine']);
    expect(store.find('Mine')!.genres, ['B']);
  });

  test('blank names are refused and delete works', () async {
    expect(await store.save('  ', const ActiveFilters()), isFalse);
    await store.save('X', const ActiveFilters());
    await store.delete('x');
    expect(store.all(), isEmpty);
  });
}
