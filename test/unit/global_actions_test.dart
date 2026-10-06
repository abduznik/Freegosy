import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/input/gamepad_service.dart';
import 'package:freegosy/core/input/global_actions.dart';
import 'package:freegosy/providers/ui_provider.dart';
import 'package:freegosy/ui/widgets/shoulder_owner.dart';

void main() {
  test('LB/RB switch the main tabs, within bounds', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    runGlobalAction(GameAction.r1, c, screenCount: 3);
    runGlobalAction(GameAction.r1, c, screenCount: 3);
    runGlobalAction(GameAction.r1, c, screenCount: 3);
    expect(c.read(currentTabIndexProvider), 2);
    runGlobalAction(GameAction.l1, c, screenCount: 3);
    expect(c.read(currentTabIndexProvider), 1);
  });

  test('while a screen owns LB/RB, the main tabs stay', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(shoulderOwnersProvider.notifier).state = 1;
    runGlobalAction(GameAction.r1, c, screenCount: 3);
    expect(c.read(currentTabIndexProvider), 0);
  });

  test('A runs the focused item', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    var ran = 0;
    c.read(focusedActionProvider.notifier).state = () => ran++;
    runGlobalAction(GameAction.confirm, c, screenCount: 3);
    expect(ran, 1);
  });

  testWidgets('ShoulderOwner owns LB/RB while it is on screen', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final show = ValueNotifier(true);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, on, _) => on ? const ShoulderOwner(child: Text('page')) : const Text('gone'),
        ),
      ),
    ));
    await tester.pump();
    expect(c.read(shoulderOwnersProvider), 1);
    show.value = false;
    await tester.pump();
    await tester.pump();
    expect(c.read(shoulderOwnersProvider), 0);
  });
}
