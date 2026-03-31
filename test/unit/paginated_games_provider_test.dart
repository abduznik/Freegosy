import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/providers/paginated_games_provider.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'paginated_games_provider_test.mocks.dart';

@GenerateMocks([RommService])
void main() {
  late MockRommService mockRommService;
  late ProviderContainer container;

  setUp(() {
    mockRommService = MockRommService();
    container = ProviderContainer(
      overrides: [
        rommServiceProvider.overrideWithValue(mockRommService),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('PaginatedGamesProvider', () {
    test('loadInitial fetches first page and sets state', () async {
      final games = List.generate(
        50,
        (i) => Game(id: '$i', name: 'Game $i', platformId: 1, fileSize: 0),
      );

      when(mockRommService.getGamesPage(
        offset: 0,
        limit: 50,
        platformId: anyNamed('platformId'),
        search: anyNamed('search'),
      )).thenAnswer((_) async => (games: games, total: 100));

      await container.read(paginatedGamesProvider.notifier).loadInitial();

      final state = container.read(paginatedGamesProvider);
      expect(state.games.length, 50);
      expect(state.total, 100);
      expect(state.hasMore, isTrue);
      expect(state.isLoading, isFalse);
    });

    test('loadMore appends next page', () async {
      final page1 = List.generate(
        50,
        (i) => Game(id: '$i', name: 'Game $i', platformId: 1, fileSize: 0),
      );
      final page2 = List.generate(
        50,
        (i) => Game(id: '${i + 50}', name: 'Game ${i + 50}', platformId: 1, fileSize: 0),
      );

      when(mockRommService.getGamesPage(
        offset: 0,
        limit: 50,
        platformId: anyNamed('platformId'),
        search: anyNamed('search'),
      )).thenAnswer((_) async => (games: page1, total: 100));

      when(mockRommService.getGamesPage(
        offset: 50,
        limit: 50,
        platformId: anyNamed('platformId'),
        search: anyNamed('search'),
      )).thenAnswer((_) async => (games: page2, total: 100));

      final notifier = container.read(paginatedGamesProvider.notifier);
      await notifier.loadInitial();
      await notifier.loadMore();

      final state = container.read(paginatedGamesProvider);
      expect(state.games.length, 100);
      expect(state.hasMore, isFalse);
    });

    test('Empty result on first page sets state to empty list', () async {
      when(mockRommService.getGamesPage(
        offset: 0,
        limit: 50,
        platformId: anyNamed('platformId'),
        search: anyNamed('search'),
      )).thenAnswer((_) async => (games: <Game>[], total: 0));

      await container.read(paginatedGamesProvider.notifier).loadInitial();

      final state = container.read(paginatedGamesProvider);
      expect(state.games, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });
  });
}
