import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/providers/paginated_games_provider.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/ui/screens/library_screen.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freegosy/core/storage/rom_mapping_service.dart';
import 'library_screen_test.mocks.dart';

@GenerateMocks([RommService, DirectoryService, RomMappingService])
void main() {
  late MockRommService mockRommService;
  late MockDirectoryService mockDirectoryService;
  late MockRomMappingService mockRomMappingService;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    mockRommService = MockRommService();
    mockDirectoryService = MockDirectoryService();
    mockRomMappingService = MockRomMappingService();
    
    when(mockRommService.config).thenReturn(RomMConfig(baseUrl: 'https://test.com', username: 'u', password: 'p'));
    when(mockRommService.resolveCoverUrl(any)).thenReturn(null);
    when(mockRommService.getRecentlyPlayed(limit: anyNamed('limit'))).thenAnswer((_) async => []);
    when(mockRommService.searchRoms(search: anyNamed('search'), platformId: anyNamed('platformId'))).thenAnswer((_) async => []);
    when(mockRommService.isOffline).thenReturn(ValueNotifier<bool>(false));
    when(mockDirectoryService.status).thenReturn(const StorageStatus());
    when(mockRomMappingService.getMappings()).thenReturn({});
    when(mockRomMappingService.getMTimes()).thenReturn({});
  });

  group('LibraryScreen', () {
    testWidgets('shows loading skeleton while games are fetching', (WidgetTester tester) async {
      when(mockRommService.getPlatforms()).thenAnswer((_) async => []);
      
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          rommServiceProvider.overrideWithValue(mockRommService),
          romMappingServiceProvider.overrideWith((ref) => Future.value(mockRomMappingService)),
          romScannerServiceProvider.overrideWithValue(null),
          directoryServiceProvider.overrideWith((ref) => Future.value(mockDirectoryService)),
          paginatedGamesProvider.overrideWith((ref) => PaginatedGamesNotifier(ref)..state = const PaginatedGamesState(isLoading: true)),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ));

      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('shows game grid when games are loaded', (WidgetTester tester) async {
      final games = [
        Game(id: '1', name: 'Game 1', platformDisplayName: 'GBA', fileSize: 0),
        Game(id: '2', name: 'Game 2', platformDisplayName: 'GBA', fileSize: 0),
      ];

      when(mockRommService.getPlatforms()).thenAnswer((_) async => []);
      when(mockDirectoryService.isRomDownloaded(any)).thenAnswer((_) async => false);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          rommServiceProvider.overrideWithValue(mockRommService),
          romMappingServiceProvider.overrideWith((ref) => Future.value(mockRomMappingService)),
          romScannerServiceProvider.overrideWithValue(null),
          directoryServiceProvider.overrideWith((ref) => Future.value(mockDirectoryService)),
          paginatedGamesProvider.overrideWith((ref) => PaginatedGamesNotifier(ref)..state = PaginatedGamesState(games: games, total: 2, hasMore: false)),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ));

      await tester.pumpAndSettle();

      expect(find.text('Game 1'), findsOneWidget);
      expect(find.text('Game 2'), findsOneWidget);
    });

    testWidgets('shows empty state when platform has no games', (WidgetTester tester) async {
      when(mockRommService.getPlatforms()).thenAnswer((_) async => []);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          rommServiceProvider.overrideWithValue(mockRommService),
          romMappingServiceProvider.overrideWith((ref) => Future.value(mockRomMappingService)),
          romScannerServiceProvider.overrideWithValue(null),
          directoryServiceProvider.overrideWith((ref) => Future.value(mockDirectoryService)),
          isHomeSelectedProvider.overrideWith((ref) => false),
          paginatedGamesProvider.overrideWith((ref) => PaginatedGamesNotifier(ref)..state = const PaginatedGamesState(games: [], total: 0, hasMore: false)),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ));

      await tester.pumpAndSettle();

      expect(find.text('No games found'), findsOneWidget);
    });

    testWidgets('shows error state when RomM connection fails', (WidgetTester tester) async {
      when(mockRommService.getPlatforms()).thenAnswer((_) async => []);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          rommServiceProvider.overrideWithValue(mockRommService),
          romMappingServiceProvider.overrideWith((ref) => Future.value(mockRomMappingService)),
          romScannerServiceProvider.overrideWithValue(null),
          directoryServiceProvider.overrideWith((ref) => Future.value(mockDirectoryService)),
          isHomeSelectedProvider.overrideWith((ref) => false),
          paginatedGamesProvider.overrideWith((ref) => PaginatedGamesNotifier(ref)..state = const PaginatedGamesState(error: 'Connection Failed')),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ));

      await tester.pumpAndSettle();

      expect(find.text('Error: Connection Failed'), findsOneWidget);
    });
  });
}
