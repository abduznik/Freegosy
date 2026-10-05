import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/providers/ui_provider.dart';
import 'package:freegosy/ui/widgets/focus_effect_wrapper.dart';

void main() {
  // The focus ring is drawn inside the focused item: focusing must not
  // change its size, or everything around it jumps.
  testWidgets('focusing an item keeps its size and leaves its neighbours in place', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [inputModeProvider.overrideWith((ref) => InputMode.gamepad)],
      child: MaterialApp(
        home: Scaffold(
          body: Column(mainAxisSize: MainAxisSize.min, children: [
            FocusEffectWrapper(
              key: const ValueKey('item'),
              focusNode: node,
              onTap: () {},
              child: const SizedBox(width: 100, height: 40),
            ),
            const SizedBox(key: ValueKey('below'), width: 10, height: 10),
          ]),
        ),
      ),
    ));
    final size = tester.getSize(find.byKey(const ValueKey('item')));
    final below = tester.getTopLeft(find.byKey(const ValueKey('below')));

    node.requestFocus();
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const ValueKey('item'))), size);
    expect(tester.getTopLeft(find.byKey(const ValueKey('below'))), below);
  });

  testWidgets('the focus ring is 90% white on the dark theme', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [inputModeProvider.overrideWith((ref) => InputMode.gamepad)],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: FocusEffectWrapper(focusNode: node, onTap: () {}, child: const SizedBox(width: 100, height: 40)),
        ),
      ),
    ));
    node.requestFocus();
    await tester.pumpAndSettle();
    final ring = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).foregroundDecoration as BoxDecoration;
    expect((ring.border as Border).top.color, Colors.white.withValues(alpha: 0.9));
  });
}
