import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/ui/widgets/storage_problem_reporter.dart';

void main() {
  late GlobalKey<ScaffoldMessengerState> key;
  late DateTime now;
  late StorageProblemReporter reporter;

  setUp(() {
    key = GlobalKey<ScaffoldMessengerState>();
    now = DateTime(2026, 10, 6, 12);
    reporter = StorageProblemReporter(key, now: () => now);
  });

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(scaffoldMessengerKey: key, home: const Scaffold(body: SizedBox())));

  testWidgets('a problem reported before the app is up is shown once it is', (tester) async {
    // e.g. a damaged settings file found by SharedPreferences.getInstance() before runApp.
    reporter.report('Settings file was damaged');
    await pumpApp(tester);
    reporter.showPending();
    await tester.pump();
    expect(find.text('Settings file was damaged'), findsOneWidget);
  });

  testWidgets('holding a message back does not start the 30 s quiet period', (tester) async {
    reporter.report('early');
    await pumpApp(tester);
    now = now.add(const Duration(seconds: 5));
    reporter.report('later');
    await tester.pump();
    expect(find.text('later'), findsOneWidget);
  });

  testWidgets('messages within 30 s of a shown one are only logged', (tester) async {
    await pumpApp(tester);
    reporter.report('first');
    now = now.add(const Duration(seconds: 10));
    reporter.report('second');
    await tester.pump();
    expect(find.text('first'), findsOneWidget);
    // Snackbars queue; the second one must never have been queued.
    key.currentState!.hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
  });

  testWidgets('showPending does nothing without a pending message', (tester) async {
    await pumpApp(tester);
    reporter.showPending();
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });
}
