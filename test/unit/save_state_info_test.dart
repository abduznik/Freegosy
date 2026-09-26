import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/save_state_info.dart';

void main() {
  group('sameEmulatorVersion', () {
    test('ignores a leading v and trailing zero parts', () {
      expect(sameEmulatorVersion('v2.8.2', '2.8.2.0'), isTrue);
      expect(sameEmulatorVersion('V2.8', '2.8.0.0'), isTrue);
    });
    test('different numbers differ', () {
      expect(sameEmulatorVersion('v2.6.0', '2.8.2.0'), isFalse);
      expect(sameEmulatorVersion('2.8.2', '2.8.2.1'), isFalse);
    });
    test('compares non-numeric versions as trimmed strings', () {
      expect(sameEmulatorVersion(' nightly-abc ', 'nightly-abc'), isTrue);
      expect(sameEmulatorVersion('nightly-abc', 'nightly-abd'), isFalse);
      expect(sameEmulatorVersion('v2.8.2-dirty', '2.8.2'), isFalse);
    });
  });

  group('compatOf', () {
    test('unknown when either side is null', () {
      expect(compatOf(null, '2.8.2.0'), StateCompat.unknown);
      expect(compatOf('v2.8.2', null), StateCompat.unknown);
      expect(compatOf(null, null), StateCompat.unknown);
    });
    test('ok when the same, mismatch when different', () {
      expect(compatOf('v2.8.2', '2.8.2.0'), StateCompat.ok);
      expect(compatOf('v2.6.0', '2.8.2.0'), StateCompat.mismatch);
    });
  });

  group('compareEmulatorVersions', () {
    test('a nightly/self-built version of the same release is unknown, not a mismatch', () {
      expect(compareEmulatorVersions('v2.3.72-12-gabcdef', '2.3.72.0'), StateCompat.unknown);
      expect(compareEmulatorVersions('2.3.72', 'v2.3.72-dirty'), StateCompat.unknown);
      expect(compatOf('v2.3.72-12-gabcdef', '2.3.72.0'), StateCompat.unknown);
      expect(sameEmulatorVersion('v2.3.72-12-gabcdef', '2.3.72.0'), isFalse);
    });
    test('a nightly of a different release is a mismatch', () {
      expect(compareEmulatorVersions('v2.3.72-12-gabcdef', '2.8.2.0'), StateCompat.mismatch);
      expect(compatOf('v2.3.72-12-gabcdef', '2.8.2.0'), StateCompat.mismatch);
    });
    test('plain numbers: ok when equal, mismatch otherwise', () {
      expect(compareEmulatorVersions('v2.8.2', '2.8.2.0'), StateCompat.ok);
      expect(compareEmulatorVersions('2.8.2', '2.8.2.1'), StateCompat.mismatch);
    });
    test('the very same text is the same build, suffix or not', () {
      expect(compareEmulatorVersions('v2.3.72-12-gabcdef', ' v2.3.72-12-gabcdef'), StateCompat.ok);
      expect(sameEmulatorVersion('v2.3.72-12-gabcdef', 'v2.3.72-12-gabcdef'), isTrue);
    });
    test('non-numeric versions compare as trimmed text', () {
      expect(compareEmulatorVersions(' nightly-abc ', 'nightly-abc'), StateCompat.ok);
      expect(compareEmulatorVersions('nightly-abc', 'nightly-abd'), StateCompat.mismatch);
    });
  });

  group('StateSlot', () {
    test('labels', () {
      expect(const AutoStateSlot().label, 'Resume (saved on exit)');
      expect(const NumberedStateSlot(3).label, 'Slot 3');
      expect(const UnknownStateSlot('x.sav').label, 'x.sav');
    });
    test('value equality', () {
      expect(const NumberedStateSlot(1), const NumberedStateSlot(1));
      expect(const NumberedStateSlot(1) == const NumberedStateSlot(2), isFalse);
      expect(const AutoStateSlot(), const AutoStateSlot());
      expect(const UnknownStateSlot('a'), const UnknownStateSlot('a'));
    });
  });
}
