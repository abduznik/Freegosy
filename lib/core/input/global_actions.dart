import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ui_provider.dart';
import 'gamepad_service.dart';

/// How many open screens use LB/RB themselves (their own tabs). While any
/// does, LB/RB don't switch the app's main tabs.
final shoulderOwnersProvider = StateProvider<int>((ref) => 0);

/// The app-wide part of [action]: A runs the focused item, A held its
/// long-press, and LB/RB switch between the [screenCount] main tabs unless
/// a screen owns them (see ShoulderOwner).
void runGlobalAction(GameAction action, ProviderContainer container, {required int screenCount}) {
  switch (action) {
    case GameAction.confirm:
      container.read(focusedActionProvider)?.call();
    case GameAction.confirmHold:
      container.read(focusedLongPressActionProvider)?.call();
    case GameAction.l1 || GameAction.r1:
      if (container.read(shoulderOwnersProvider) > 0) return;
      final current = container.read(currentTabIndexProvider);
      final next = action == GameAction.l1 ? current - 1 : current + 1;
      if (next >= 0 && next < screenCount) container.read(currentTabIndexProvider.notifier).state = next;
    default:
      break;
  }
}
