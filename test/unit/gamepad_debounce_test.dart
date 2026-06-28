import 'package:flutter_test/flutter_test.dart';

/// Simulates the debounce logic from GamepadService for issue #41.
class DebounceSimulator {
  final Map<String, DateTime> _lastPress = {};
  final Duration debounceWindow;

  DebounceSimulator({this.debounceWindow = const Duration(milliseconds: 80)});

  /// Returns true if the press should be processed (not a ghost).
  bool shouldProcess(String action, DateTime timestamp) {
    final lastPress = _lastPress[action];
    if (lastPress != null && timestamp.difference(lastPress) < debounceWindow) {
      return false; // Ghost press
    }
    _lastPress[action] = timestamp;
    return true;
  }
}

void main() {
  group('Issue #41 — Gamepad debounce logic', () {
    late DebounceSimulator debounce;

    setUp(() {
      debounce = DebounceSimulator();
    });

    test('first press is always processed', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      expect(debounce.shouldProcess('confirm', now), isTrue);
    });

    test('rapid second press within debounce window is ignored', () {
      final t1 = DateTime(2026, 1, 1, 12, 0, 0, 0);
      final t2 = DateTime(2026, 1, 1, 12, 0, 0, 50); // 50ms later

      expect(debounce.shouldProcess('confirm', t1), isTrue);
      expect(debounce.shouldProcess('confirm', t2), isFalse); // Ghost
    });

    test('press after debounce window is processed', () {
      final t1 = DateTime(2026, 1, 1, 12, 0, 0, 0);
      final t2 = DateTime(2026, 1, 1, 12, 0, 0, 100); // 100ms later (> 80ms)

      expect(debounce.shouldProcess('confirm', t1), isTrue);
      expect(debounce.shouldProcess('confirm', t2), isTrue);
    });

    test('different actions debounce independently', () {
      final t1 = DateTime(2026, 1, 1, 12, 0, 0, 0);
      final t2 = DateTime(2026, 1, 1, 12, 0, 0, 10); // 10ms later

      expect(debounce.shouldProcess('confirm', t1), isTrue);
      expect(debounce.shouldProcess('back', t2), isTrue); // Different action
    });

    test('hold-to-repeat still works after debounce window', () {
      final t1 = DateTime(2026, 1, 1, 12, 0, 0, 0);
      final t2 = DateTime(2026, 1, 1, 12, 0, 0, 50); // Ghost
      final t3 = DateTime(2026, 1, 1, 12, 0, 0, 100); // Processed
      final t4 = DateTime(2026, 1, 1, 12, 0, 0, 150); // Ghost
      final t5 = DateTime(2026, 1, 1, 12, 0, 0, 200); // Processed

      expect(debounce.shouldProcess('down', t1), isTrue);
      expect(debounce.shouldProcess('down', t2), isFalse);
      expect(debounce.shouldProcess('down', t3), isTrue);
      expect(debounce.shouldProcess('down', t4), isFalse);
      expect(debounce.shouldProcess('down', t5), isTrue);
    });

    test('burst of 5 rapid presses within 40ms only processes first', () {
      final base = DateTime(2026, 1, 1, 12, 0, 0, 0);
      int processed = 0;
      for (int i = 0; i < 5; i++) {
        if (debounce.shouldProcess('up', base.add(Duration(milliseconds: i * 10)))) {
          processed++;
        }
      }
      expect(processed, 1);
    });

    test('custom debounce window works', () {
      final custom = DebounceSimulator(debounceWindow: Duration(milliseconds: 200));
      final t1 = DateTime(2026, 1, 1, 12, 0, 0, 0);
      final t2 = DateTime(2026, 1, 1, 12, 0, 0, 150); // Within 200ms

      expect(custom.shouldProcess('confirm', t1), isTrue);
      expect(custom.shouldProcess('confirm', t2), isFalse);
    });
  });
}
