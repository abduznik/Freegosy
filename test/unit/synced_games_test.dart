import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/synced_games.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/ui/widgets/game_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a pull or a pushed file hash marks the game as synced', () {
    expect(syncedGameIds(['last_pull_12', 'last_hash_34_Game.ram', 'last_hash_34_Game.rtc', 'other', 'last_hash_', 'last_pull_']),
        {'12', '34'});
  });

  test('no records, nobody synced', () => expect(syncedGameIds(['theme', 'update_channel']), isEmpty));

  Future<Widget> card({required bool downloaded, required Map<String, Object> prefs}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: MaterialApp(
        home: SizedBox(width: 160, height: 240, child: GameCard(game: Game(id: '12', name: 'Emerald', fileSize: 1), isDownloaded: downloaded)),
      ),
    );
  }

  testWidgets('a downloaded, synced game shows the cloud badge', (t) async {
    await t.pumpWidget(await card(downloaded: true, prefs: {'last_pull_12': '2026-01-01T00:00:00'}));
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });

  testWidgets('no badge when never synced, or when not downloaded', (t) async {
    await t.pumpWidget(await card(downloaded: true, prefs: {}));
    expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
    await t.pumpWidget(await card(downloaded: false, prefs: {'last_pull_12': 'x'}));
    expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
  });

  testWidgets('a card without preferences wired in still builds', (t) async {
    await t.pumpWidget(ProviderScope(child: MaterialApp(home: SizedBox(width: 160, height: 240, child: GameCard(game: Game(id: '1', name: 'X', fileSize: 1), isDownloaded: true)))));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
