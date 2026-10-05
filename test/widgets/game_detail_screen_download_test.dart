import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:freegosy/ui/screens/game_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Returns [_fullGame] from getGame(), simulating the server response after
/// a full detail fetch (as GameDetailScreen's _refreshGame() performs).
class _FakeRommService extends RommService {
  _FakeRommService(super.config, this._fullGame)
      : super(skipConnectivityCheck: true);

  final Game _fullGame;

  @override
  Future<Game?> getGame(String id) async => _fullGame;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  // Regression test for the "DOOM II" bug: GameDetailScreen fetches full rom
  // details (with files[] populated) into _currentGame via _refreshGame(),
  // but the Download button used to invoke widget.onDownload() with no
  // arguments, so callers (library_screen.dart) closed over the ORIGINAL
  // list-sourced Game (files: []) from before navigation instead. The
  // freshly-fetched, fully-populated game was silently discarded.
  testWidgets('Download button passes the freshly-refreshed game (with files[]), not the stale one', (tester) async {
    final prefs = await SharedPreferences.getInstance();

    // The game as it looks coming from the paginated library list: RomM's
    // list endpoint always returns files: [] regardless of rom layout.
    final staleListGame = Game(
      id: '37337',
      name: 'DOOM II',
      fsName: 'doom 2',
      fsExtension: '',
      fileSize: 26214912,
      files: const [],
    );

    // The game as it looks after a full getGame() fetch: files[] carries
    // the real per-file id + file_name (with the correct extension).
    final refreshedFullGame = Game(
      id: '37337',
      name: 'DOOM II',
      fsName: 'doom 2',
      fsExtension: '',
      fileSize: 26214912,
      files: const [
        {'id': 41272, 'file_name': 'doom 2.vhd'},
      ],
    );

    final config = RomMConfig(baseUrl: 'https://romm.example.com', username: 'u', password: 'p', apiKey: 'k');
    final fakeService = _FakeRommService(config, refreshedFullGame);

    Game? gamePassedToDownload;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          romScannerServiceProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          home: GameDetailScreen(
            game: staleListGame,
            rommBaseUrl: config.baseUrl,
            isDownloaded: false,
            rommService: fakeService,
            onPlay: (_) async => true,
            onDownload: (game) async {
              gamePassedToDownload = game;
            },
            onPushSaves: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    // Let _refreshGame()'s async getGame() call resolve and rebuild state.
    await tester.pumpAndSettle();

    await tester.tap(find.text('⭳ Download'));
    await tester.pump();

    expect(gamePassedToDownload, isNotNull);
    expect(gamePassedToDownload!.files, isNotEmpty);
    expect(gamePassedToDownload!.files.first['file_name'], 'doom 2.vhd');
  });
}
