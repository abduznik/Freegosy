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
  /// - `dwpov` / `pov*`        — DirectInput / generic POV hat → all D-pad directions
  /// - `hat*`                  — Some Linux joydev hat keys (e.g. "hat0x", "hat0y")
  /// - `dpadup` / `dpaddown`   — GameInput digital d-pad buttons → all D-pad directions
  /// - Numeric-only keys       — /dev/input/js* reports hat switches as bare numbers
  ///                             (e.g. "6" and "7" for the DS4 emulation layer).
  ///                             When we see a polarity-encoded variant ("6+" / "6-")
  ///                             that maps to a D-pad action in the sniffed mapping,
  ///                             we know the hat is being handled. We detect this by
  ///                             checking whether the seen-keys contain ANY polarity
  ///                             suffix on a numeric key — i.e. the wizard already
  ///                             captured them.
  /// - `dwxpos` / `dwypos`     — DirectInput named axes → analog stick axes handled
  /// - `leftthumbstickx` etc.  — GameInput named axes → analog stick axes handled
  static Set<GameAction> backendHandledActions(Set<String> seenKeys) {
    final handled = <GameAction>{};

    // POV hat (DirectInput / generic)
    if (seenKeys.any((k) => k == 'dwpov' || k.startsWith('pov') || k.startsWith('hat'))) {
      handled.addAll([GameAction.up, GameAction.down, GameAction.left, GameAction.right]);
    }

    // GameInput digital d-pad buttons
    if (seenKeys.any((k) => k == 'dpadup' || k == 'dpaddown' || k == 'dpadleft' || k == 'dpadright')) {
      handled.addAll([GameAction.up, GameAction.down, GameAction.left, GameAction.right]);
    }

    // DirectInput named analog axes
    if (seenKeys.any((k) => k == 'dwxpos' || k == 'dwypos')) {
      handled.addAll([GameAction.horizontalAxis, GameAction.verticalAxis]);
    }

    // GameInput named analog axes
    if (seenKeys.any((k) => k == 'leftthumbstickx' || k == 'leftthumbsticky')) {
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

  /// Rescales a raw axis value to the -1.0..1.0 range press/release
  /// thresholds are written against.
  ///
  /// Linux (/dev/input/js*) reports raw int16 magnitudes for axes (roughly
  /// -32767..32767) instead of the normalized range other backends deliver.
  /// Left as-is, any nonzero jitter on an idle axis reads as fully "pressed"
  /// and almost never "released". Values already within -1.0..1.0 are
  /// returned unchanged.
  ///
  /// This only fixes the *threshold miscalibration* — it rescales magnitude,
  /// nothing more. It does not arbitrate between multiple axes/buttons that
  /// report real, simultaneous activity (e.g. a controller whose D-pad
  /// physically drives more than one raw axis at once). On marginal or
  /// noisy pads the wizard's charge can still occasionally get preempted by
  /// a second input; this reduces how often that happens, it doesn't
  /// guarantee it can't.
  static double normalizeAxisValue(double value) {
    if (value.abs() <= 1.0) return value;
    return (value / 32767.0).clamp(-1.0, 1.0);
  }

  /// Named DirectInput axis keys that report unsigned 0..65535 magnitudes
  /// (center ~32767) instead of the signed int16 range Linux joydev axes use.
  static const Set<String> _directInputUnsignedAxisKeys = {
    'dwxpos', 'dwypos', 'dwrpos', 'dwupos', 'dwvpos',
  };

  /// Rescales a raw axis value to -1.0..1.0, choosing the correct convention
  /// for the reporting backend based on the raw key name.
  ///
  /// On Windows, "generic"/DirectInput controllers report named axes
  /// (dwXpos/dwYpos/dwRpos/dwUpos/dwVpos) as UNSIGNED magnitudes in
  /// 0..65535 with the centered/idle position at ~32767 — this is a
  /// completely different convention from the signed ~-32767..32767 range
  /// [normalizeAxisValue] handles for Linux /dev/input/js*. Feeding a
  /// DirectInput value straight into [normalizeAxisValue] misreads it: e.g.
  /// a lightly-deflected axis sitting at ~40000 gets divided by 32767 and
  /// clamped to 1.0, i.e. it reads as fully pressed in every direction —
  /// this is what made the manual controller-mapping wizard bind every
  /// action to "both analog sticks" for Windows DirectInput ("generic
  /// Windows controller") pads.
  ///
  /// This mirrors the same `(value - 32767.0) / 32767.0` conversion already
  /// used as the reference implementation in GamepadService._normalize()
  /// for the main input pipeline.
  static double normalizeAxisValueForKey(String rawKey, double value) {
    if (_directInputUnsignedAxisKeys.contains(rawKey.toLowerCase())) {
      return ((value - 32767.0) / 32767.0).clamp(-1.0, 1.0);
    }
    return normalizeAxisValue(value);
  }

  /// Tags a bare numeric raw key with its event type before any polarity
  /// suffix is applied.
  ///
  /// On Linux (/dev/input/js*), a button and an axis can share the same raw
  /// index — e.g. the Xbox 360 pad reports Back as button 6 and the D-pad's
  /// horizontal axis as axis 6, both arriving as `key: "6"`. Left un-tagged,
  /// mapping either one stomps the other. Named keys (letters/underscores,
  /// e.g. `dpad_up`, `button_0`) are already unambiguous on every other
  /// backend and are returned unchanged.
  static String disambiguateKey(String rawKey, {required bool isButton}) {
    if (!RegExp(r'^\d+$').hasMatch(rawKey)) return rawKey;
    return (isButton ? 'btn' : 'ax') + rawKey;
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
