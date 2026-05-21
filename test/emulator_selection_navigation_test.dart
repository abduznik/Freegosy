import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/ui/widgets/emulator_selection_dialog.dart';

void main() {
  testWidgets('EmulatorSelectionDialog should only trigger onSelect and NOT pop itself internally', (WidgetTester tester) async {
    bool onSelectCalled = false;
    String selectedUrl = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => EmulatorSelectionDialog(
                      assets: [
                        {'name': 'v1.0.0', 'url': 'https://test.com/v1'},
                        {'name': 'v2.0.0', 'url': 'https://test.com/v2'},
                      ],
                      onSelect: (url) {
                        onSelectCalled = true;
                        selectedUrl = url;
                        // The caller is responsible for popping the dialog if needed
                        Navigator.of(ctx).pop('result');
                      },
                    ),
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    // 1. Open the dialog
    await tester.tap(find.text('Show Dialog'));
    await tester.pumpAndSettle();

    expect(find.byType(EmulatorSelectionDialog), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);

    // 2. Tap an item
    await tester.tap(find.text('v1.0.0'));
    await tester.pumpAndSettle();

    // 3. Verify onSelect was called
    expect(onSelectCalled, true);
    expect(selectedUrl, 'https://test.com/v1');

    // 4. Verify the dialog is gone (because we called pop in onSelect)
    expect(find.byType(EmulatorSelectionDialog), findsNothing);

    // 5. CRITICAL: Verify the main screen (ElevatedButton) is STILL PRESENT
    // If a double-pop happened, the whole Scaffold/MaterialApp might be gone or we'd be at a black screen (root)
    expect(find.text('Show Dialog'), findsOneWidget);
  });

  testWidgets('EmulatorSelectionDialog should not crash if onSelect does not pop (though it should be handled by caller)', (WidgetTester tester) async {
    // This tests that the dialog itself doesn't pop anymore
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => EmulatorSelectionDialog(
                      assets: [
                        {'name': 'v1.0.0', 'url': 'https://test.com/v1'},
                      ],
                      onSelect: (url) {
                        // We intentionally DON'T pop here to see if the widget pops itself
                      },
                    ),
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show Dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('v1.0.0'));
    await tester.pumpAndSettle();

    // Verify dialog is STILL PRESENT because we didn't pop in onSelect
    // If it's NOT present, it means the widget is still popping itself internally (which we want to avoid)
    expect(find.byType(EmulatorSelectionDialog), findsOneWidget);
  });
}
