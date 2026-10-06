import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/portable/portable_mode.dart';
import 'package:freegosy/ui/screens/portable_error_app.dart';

void main() {
  testWidgets('a startup failure is shown with a Quit button', (tester) async {
    showStartupError(StateError('box is read-only'));
    await tester.pump();
    expect(find.textContaining('Freegosy could not start'), findsOneWidget);
    expect(find.textContaining('box is read-only'), findsOneWidget);
    expect(find.text('Quit'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('a portable folder that cannot be written offers to start without portable mode', (tester) async {
    final choice = showPortableError(PortableModeException(r'E:\Freegosy', 'Access is denied'));
    await tester.pump();
    expect(find.textContaining(r"can't write to E:\Freegosy"), findsOneWidget);
    await tester.tap(find.text('Start without portable mode this time'));
    expect(await choice, isTrue);
  });
}
