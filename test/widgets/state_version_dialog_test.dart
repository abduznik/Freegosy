import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/ui/widgets/state_version_dialog.dart';

void main() {
  /// Pumps a button that opens the dialog; every result lands in [results].
  Future<void> pumpOpener(WidgetTester tester, List<bool> results) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(await showStateVersionDialog(context,
                  slotLabel: 'Slot 3',
                  emulatorName: 'PCSX2',
                  stateVersion: 'v2.6.0',
                  installed: '2.8.2.0')),
              child: const Text('open'),
            ),
          ),
        ),
      ));

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows both versions and focuses Cancel', (tester) async {
    await pumpOpener(tester, []);
    await open(tester);
    expect(find.text('Slot 3 was made with PCSX2 v2.6.0, you have 2.8.2.0. It may not load.'),
        findsOneWidget);
    final focused = tester.binding.focusManager.primaryFocus?.context;
    expect(focused, isNotNull);
    expect(
        find.descendant(
            of: find.widgetWithText(TextButton, 'Cancel'), matching: find.byWidget(focused!.widget)),
        findsOneWidget);
  });

  testWidgets('Cancel is false, Load anyway is true', (tester) async {
    final results = <bool>[];
    await pumpOpener(tester, results);
    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await open(tester);
    await tester.tap(find.text('Load anyway'));
    await tester.pumpAndSettle();
    expect(results, [false, true]);
  });

  testWidgets('tapping outside counts as Cancel', (tester) async {
    final results = <bool>[];
    await pumpOpener(tester, results);
    await open(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });
}
