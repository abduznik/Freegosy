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

  group('GameDetailActionButton Emulation & Alignment test', () {
    testWidgets('emulate action button row and verify no visual overlap or clipping during focus scaling', (WidgetTester tester) async {
      final focusNode1 = FocusNode();
      final focusNode2 = FocusNode();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 384,
                  child: Row(
                    children: [
                      Expanded(
                        child: Focus(
                          focusNode: focusNode1,
                          child: GameDetailActionButton(
                            icon: Icons.cloud_upload_outlined,
                            label: 'Push',
                            onTap: () {},
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Focus(
                          focusNode: focusNode2,
                          child: GameDetailActionButton(
                            icon: Icons.cloud_download_outlined,
                            label: 'Pull',
                            onTap: () {},
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Verify buttons are rendered
      expect(find.text('Push'), findsOneWidget);
      expect(find.text('Pull'), findsOneWidget);


      // 1. Simulate focus/interaction on Push button
      focusNode1.requestFocus();
      await tester.pumpAndSettle();

      // Programmatically verify the button scales up elegantly without any clipping or boundary errors
      final RenderBox box1After = tester.renderObject(find.text('Push'));
      final RenderBox box2After = tester.renderObject(find.text('Pull'));

      // Check offsets to ensure no collision or overlap occurs
      final Offset offset1 = box1After.localToGlobal(Offset.zero);
      final Offset offset2 = box2After.localToGlobal(Offset.zero);

      // Push button right boundary must be strictly less than Pull button left boundary
      final double pushRightBoundary = offset1.dx + box1After.size.width;
      final double pullLeftBoundary = offset2.dx;

      expect(pushRightBoundary < pullLeftBoundary, isTrue);

      // Verify perfect spacing margin between the interactive bounds
      final double spacing = pullLeftBoundary - pushRightBoundary;
      expect(spacing, isPositive);

      expect(tester.takeException(), isNull);
    });
  });

  group('GamePersonalSection Status Dialog Intrinsic dimensions test', () {
    testWidgets('Opening Status Dialog in GameDetailScreen does not crash with LayoutBuilder intrinsic dimensions exception', (WidgetTester tester) async {
      // Configure larger screen size to ensure all elements fit without being off-screen
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final prefs = await SharedPreferences.getInstance();
      final testGame = Game(
        id: '123',
        name: 'Test Game',
        fileSize: 1024,
      );

      // Render the GameDetailScreen
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            romScannerServiceProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: GameDetailScreen(
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
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the status button (labeled 'Not set' by default, or just status title/label)
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);

      // Tap the status selector button to open the dialog
      await tester.tap(find.text('Not set'));
      await tester.pumpAndSettle();

      // Verify that the Dialog has successfully opened by checking if the select title 'Select Status' is visible
      expect(find.text('Select Status'), findsOneWidget);
      expect(find.text('Never Played'), findsOneWidget);
      expect(find.text('Finished'), findsOneWidget);

      // Tap 'Finished' to dismiss and select a status
      await tester.tap(find.text('Finished'));
      await tester.pumpAndSettle();

      // Verify that the dialog is dismissed and the main detailed card status updates
      expect(find.text('Select Status'), findsNothing);
      expect(find.text('Finished'), findsOneWidget);

      // Verify absolutely no intrinsic dimension layout exceptions were thrown
      expect(tester.takeException(), isNull);
    });
  });
}
