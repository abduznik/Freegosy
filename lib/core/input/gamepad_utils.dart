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
  ///
  /// Detects:
  /// - `dwpov` / `pov*`   — DirectInput / generic POV hat → all D-pad directions
  /// - `hat*`             — Some Linux joydev hat keys (e.g. "hat0x", "hat0y")
  /// - Numeric-only keys  — /dev/input/js* reports hat switches as bare numbers
  ///                        (e.g. "6" and "7" for the DS4 emulation layer).
  ///                        When we see a polarity-encoded variant ("6+" / "6-")
  ///                        that maps to a D-pad action in the sniffed mapping,
  ///                        we know the hat is being handled. We detect this by
  ///                        checking whether the seen-keys contain ANY polarity
  ///                        suffix on a numeric key — i.e. the wizard already
  ///                        captured them.
  /// - `dwxpos` / `dwypos` — DirectInput named axes → analog stick axes handled
  static Set<GameAction> backendHandledActions(Set<String> seenKeys) {
    final handled = <GameAction>{};

    // POV hat (DirectInput / generic)
    if (seenKeys.any((k) => k == 'dwpov' || k.startsWith('pov') || k.startsWith('hat'))) {
      handled.addAll([GameAction.up, GameAction.down, GameAction.left, GameAction.right]);
    }

    // DirectInput named analog axes
    if (seenKeys.any((k) => k == 'dwxpos' || k == 'dwypos')) {
      handled.addAll([GameAction.horizontalAxis, GameAction.verticalAxis]);
    }

    return handled;
  }

  /// Encodes a raw key + polarity into the storage format used by both the
  /// sniff wizard and the runtime normaliser.
  ///
  /// - Digital buttons (value ≥ 0.5): stored as plain key, e.g. `"button_0"`
  /// - Axes / hat-switch directions: stored with polarity suffix, e.g. `"6+"` or `"7-"`
  ///
  /// This mirrors the Dolphin / RetroArch convention:
  ///   Axis 0+  →  positive deflection (right / down)
  ///   Axis 0-  →  negative deflection (left / up)
  static String encodeKey(String rawKey, int polarity) {
    return '$rawKey${polarity >= 0 ? '+' : '-'}';
  }

  /// Whether a stored key has a polarity suffix (i.e. it came from an axis).
  static bool hasPolaritySuffix(String key) {
    return key.endsWith('+') || key.endsWith('-');
  }

  /// Strips the polarity suffix and returns (bareKey, polarity).
  /// If the key has no suffix, polarity is returned as 0.
  static (String, int) decodeKey(String key) {
    if (key.endsWith('+')) return (key.substring(0, key.length - 1), 1);
    if (key.endsWith('-')) return (key.substring(0, key.length - 1), -1);
    return (key, 0);
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
