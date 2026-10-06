import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:freegosy/ui/widgets/save_list/save_waiting.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SaveSyncService sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final dirs = DirectoryService(prefs);
    sync = SaveSyncService(RommService(RomMConfig(baseUrl: '', username: '', password: '')), dirs,
        StrategyRegistry(dirs, prefs), prefs);
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(ProviderScope(
        overrides: [saveSyncServiceProvider.overrideWith((ref) async => sync)],
        child: const MaterialApp(home: Scaffold(body: SaveWaiting())),
      ));

  testWidgets('while another save operation runs, the list says what it waits for', (tester) async {
    sync.debugSetActivity("Uploading Mario Kart 64's save");
    await pump(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text("Waiting for: Uploading Mario Kart 64's save"), findsOneWidget);

    sync.debugSetActivity(null);
    await tester.pump();
    expect(find.textContaining('Waiting for'), findsNothing);
  });
}
