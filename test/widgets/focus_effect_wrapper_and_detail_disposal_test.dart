import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/providers/ui_provider.dart';
import 'package:freegosy/ui/widgets/focus_effect_wrapper.dart';
import 'package:freegosy/ui/screens/game_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/providers/romm_provider.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('FocusEffectWrapper Build-Phase Safety & didUpdateWidget test', () {
    testWidgets('FocusEffectWrapper updates onTap during didUpdateWidget cleanly without build exception', (WidgetTester tester) async {
      int clickCount = 0;
      void tapCallback1() { clickCount = 1; }
      void tapCallback2() { clickCount = 2; }

      // Stateful container to toggle onTap callback
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      FocusEffectWrapper(
                        onTap: clickCount == 0 ? tapCallback1 : tapCallback2,
                        child: const Text('Test Wrapper'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            clickCount = 99; // triggers didUpdateWidget rebuild
                          });
                        },
                        child: const Text('Rebuild'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Verify widget rendered
      expect(find.text('Test Wrapper'), findsOneWidget);

      // Focus it to make sure _isFocused is true, which triggers didUpdateWidget ref state modifications
      final focusNode = tester.widget<Focus>(
        find.descendant(
          of: find.byType(FocusEffectWrapper),
          matching: find.byType(Focus),
        ).first,
      ).focusNode;
      focusNode?.requestFocus();
      await tester.pumpAndSettle();

      // Trigger rebuild which invokes didUpdateWidget with changed onTap callback
      await tester.tap(find.text('Rebuild'));
      await tester.pump();

      // Verify no exception was thrown, and the widget hierarchy completed rebuilding cleanly!
      expect(tester.takeException(), isNull);
    });
  });

  group('GameDetailScreen Safe Disposal test', () {
    testWidgets('pop and dispose detail screen safely cleans up navigationLockedProvider without unmounted/disposed ref exception', (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      final testGame = Game(
        id: '123',
        name: 'Test Game',
        fileSize: 1024,
      );

      // We render a simple route switcher so we can push and pop the detail screen cleanly
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            romScannerServiceProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => GameDetailScreen(
                            game: testGame,
                            rommBaseUrl: 'http://test',
                            isDownloaded: false,
                            onLaunch: () {},
                            onDownload: () {},
                            onPushSaves: () {},
                            onPullSaves: () {},
                            onDelete: () {},
                          ),
                        ),
                      );
                    },
                    child: const Text('Push Screen'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // 1. Push screen
      await tester.tap(find.text('Push Screen'));
      await tester.pumpAndSettle();

      // Verify screen is showing
      expect(find.text('Test Game'), findsOneWidget);

      // 2. Lock navigation
      final element = tester.element(find.byType(GameDetailScreen));
      final container = ProviderScope.containerOf(element);
      container.read(navigationLockedProvider.notifier).state = true;
      expect(container.read(navigationLockedProvider), isTrue);

      // 3. Pop/Dispose screen
      Navigator.of(element).pop();
      await tester.pumpAndSettle();

      // Verify screen is disposed (no longer in widget tree)
      expect(find.text('Test Game'), findsNothing);

      // Verify that navigationLockedProvider was safely reset to false upon disposal without throwing any exceptions!
      expect(container.read(navigationLockedProvider), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
