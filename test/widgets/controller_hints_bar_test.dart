import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/providers/ui_provider.dart';
import 'package:freegosy/ui/widgets/controller_hints_bar.dart';

void main() {
  Future<void> pump(WidgetTester tester, String button, {InputMode mode = InputMode.gamepad}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [inputModeProvider.overrideWith((ref) => mode)],
      child: MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ControllerHintsBar(hints: [ControllerHintItem(label: 'Tabs', button: button)]),
        ),
      ),
    ));
  }

  Rect badgeOf(WidgetTester tester, String text) => tester.getRect(
      find.ancestor(of: find.text(text), matching: find.byType(Container)).first);

  testWidgets('a two-button badge (L1 R1) fits its text and centres it', (tester) async {
    await pump(tester, 'L1 R1');
    final text = tester.getRect(find.text('L1 R1'));
    final badge = badgeOf(tester, 'L1 R1');
    expect(badge.left, lessThan(text.left));
    expect(badge.right, greaterThan(text.right));
    final paragraph = tester.renderObject<RenderParagraph>(find.text('L1 R1'));
    expect(paragraph.size.width, greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
        reason: 'the text gets its full one-line width, not squeezed into a 24 px badge');
    expect(badge.top, lessThan(text.top));
    expect(badge.bottom, greaterThan(text.bottom));
    expect(text.center.dx, moreOrLessEquals(badge.center.dx, epsilon: 0.5));
    expect(text.center.dy, moreOrLessEquals(badge.center.dy, epsilon: 0.5));
  });

  testWidgets('a one-letter badge stays 24 px wide', (tester) async {
    await pump(tester, 'A');
    expect(badgeOf(tester, 'A').width, 24);
  });

  testWidgets('on a keyboard, L1 R1 reads Q E', (tester) async {
    await pump(tester, 'L1 R1', mode: InputMode.keyboard);
    expect(find.text('Q E'), findsOneWidget);
  });
}
