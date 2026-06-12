import 'gamepad_service.dart';

/// Pure stateless helpers extracted for testability — no plugin dependency.
class GamepadUtils {
  GamepadUtils._();

  /// Decodes a DirectInput POV hat value (hundredths of a degree) to discrete
  /// direction actions. Returns an empty list when centered (65535 or -1).
  static List<GameAction> decodePOV(double rawValue) {
    final intVal = rawValue.toInt();
    if (intVal < 0 || intVal == 65535) return [];
    final deg = intVal / 100.0;
    if (deg >= 337.5 || deg < 22.5) return [GameAction.up];
    if (deg < 67.5) return [GameAction.up, GameAction.right];
    if (deg < 112.5) return [GameAction.right];
    if (deg < 157.5) return [GameAction.down, GameAction.right];
    if (deg < 202.5) return [GameAction.down];
    if (deg < 247.5) return [GameAction.down, GameAction.left];
    if (deg < 292.5) return [GameAction.left];
    return [GameAction.up, GameAction.left];
  }

  /// Returns which GameActions are automatically handled by the backend for a
  /// given set of raw key names seen from the controller, so the sniff wizard
  /// can skip asking the user for those buttons.
  static Set<GameAction> backendHandledActions(Set<String> seenKeys) {
    final handled = <GameAction>{};

    if (seenKeys.any((k) => k == 'dwpov' || k.startsWith('pov'))) {
      handled.addAll([GameAction.up, GameAction.down, GameAction.left, GameAction.right]);
    }

    if (seenKeys.any((k) => k == 'dwxpos' || k == 'dwypos')) {
      handled.addAll([GameAction.horizontalAxis, GameAction.verticalAxis]);
    }

    return handled;
  }

  /// Splits a controller name into meaningful lowercase tokens, stripping
  /// noise words so fuzzy matching isn't thrown off by common filler terms.
  static Set<String> tokenize(String name) {
    const noise = {
      'usb', 'hid', 'gamepad', 'controller', 'joystick',
      'wireless', 'device', 'for', 'the', 'by',
    };
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1 && !noise.contains(t))
        .toSet();
  }
}
