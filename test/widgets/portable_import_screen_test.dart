import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/ui/screens/portable_import_screen.dart';

void main() {
  const importLabel = 'Import settings from the Freegosy installed on this PC';

  Future<void> pump(WidgetTester tester, {required Future<void> Function() work, required Future<void> Function() restart}) =>
      tester.pumpWidget(MaterialApp(
          home: PortableImportScreen(onStartFresh: () {}, importWork: work, restart: restart)));

  testWidgets('a failed copy says nothing was changed', (tester) async {
    await pump(tester, work: () async => throw StateError('disk full'), restart: () async {});
    await tester.tap(find.text(importLabel));
    await tester.pumpAndSettle();
    expect(find.text('Nothing was changed'), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'progress dialog closed');
  });

  testWidgets('a failed restart is not reported as a failed import', (tester) async {
    await pump(tester, work: () async {}, restart: () async => throw StateError('no exe'));
    await tester.tap(find.text(importLabel));
    await tester.pumpAndSettle();
    expect(find.text('Restart Freegosy'), findsOneWidget);
    expect(find.text('Nothing was changed'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows progress and ignores a second tap while importing', (tester) async {
    var runs = 0;
    final gate = Completer<void>();
    await pump(tester, work: () {
      runs++;
      return gate.future;
    }, restart: () async {});
    await tester.tap(find.text(importLabel));
    await tester.tap(find.text(importLabel), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(runs, 1);
    gate.complete();
    // The real restart exits the process; the progress dialog stays until then.
    await tester.pump();
    expect(runs, 1);
  });

  group('offer', () {
    test('only for a portable copy that started empty while the PC has data', () {
      expect(PortableImportScreen.offerFor(startedEmpty: true, skipOffer: false, installedHasData: true), isTrue);
      expect(PortableImportScreen.offerFor(startedEmpty: false, skipOffer: false, installedHasData: true), isFalse);
      expect(PortableImportScreen.offerFor(startedEmpty: true, skipOffer: false, installedHasData: false), isFalse);
    });

    test('never when the copy was made portable without copying', () {
      expect(PortableImportScreen.offerFor(startedEmpty: true, skipOffer: true, installedHasData: true), isFalse);
    });
  });
}
