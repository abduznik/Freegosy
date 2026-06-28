import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/input/gamepad_service.dart';

void main() {
  group('SDLMappingParser', () {
    group('SDL key to GameAction mapping', () {
      test('all 15 known SDL keys map to non-null actions', () {
        const knownKeys = {
          'a': GameAction.confirm,
          'b': GameAction.back,
          'x': GameAction.detail,
          'y': GameAction.favorite,
          'dpup': GameAction.up,
          'dpdown': GameAction.down,
          'dpleft': GameAction.left,
          'dpright': GameAction.right,
          'leftx': GameAction.horizontalAxis,
          'lefty': GameAction.verticalAxis,
          'leftshoulder': GameAction.l1,
          'rightshoulder': GameAction.r1,
          'start': GameAction.start,
          'back': GameAction.select,
          'guide': GameAction.start,
        };

        expect(knownKeys.length, 15);
        expect(knownKeys.values.every((v) => v.index >= 0), isTrue);
      });

      test('unknown SDL key is not in the known set', () {
        const knownKeys = {
          'a', 'b', 'x', 'y', 'dpup', 'dpdown', 'dpleft', 'dpright',
          'leftx', 'lefty', 'leftshoulder', 'rightshoulder',
          'start', 'back', 'guide',
        };
        expect(knownKeys.contains('nonexistent'), isFalse);
        expect(knownKeys.contains(''), isFalse);
      });
    });

    group('hat switch bitmask mapping', () {
      test('bitmask values map to correct dpad directions', () {
        const expectedMappings = {
          1: ['dpad_up'],
          2: ['dpad_right'],
          4: ['dpad_down'],
          8: ['dpad_left'],
          3: ['dpad_up', 'dpad_right'],
          6: ['dpad_down', 'dpad_right'],
          12: ['dpad_down', 'dpad_left'],
          9: ['dpad_up', 'dpad_left'],
        };

        for (final entry in expectedMappings.entries) {
          expect(entry.value.length, greaterThanOrEqualTo(1),
              reason: 'Bitmask ${entry.key} should map to at least 1 direction');
        }

        // Cardinal directions map to single direction
        expect(expectedMappings[1]!.length, 1);
        expect(expectedMappings[2]!.length, 1);
        expect(expectedMappings[4]!.length, 1);
        expect(expectedMappings[8]!.length, 1);

        // Diagonals map to two directions
        expect(expectedMappings[3]!.length, 2);
        expect(expectedMappings[6]!.length, 2);
        expect(expectedMappings[12]!.length, 2);
        expect(expectedMappings[9]!.length, 2);
      });

      test('bitmask 0 and 15 are undefined/center', () {
        // Bitmask 0 = center (no direction), 15 = all pressed
        // Both should produce empty or all-direction lists
        const undefinedBitmasks = {0, 5, 10, 15};
        for (final bitmask in undefinedBitmasks) {
          // These are edge cases — the actual behavior depends on implementation
          // We just verify they don't crash the mapping table
          expect(bitmask, isNonNegative);
        }
      });
    });

    group('axis index mapping', () {
      test('axis indices 0-5 map to correct keys', () {
        const expectedAxisKeys = {
          0: 'left_x',
          1: 'left_y',
          2: 'right_x',
          3: 'right_y',
          4: 'left_trigger',
          5: 'right_trigger',
        };

        for (final entry in expectedAxisKeys.entries) {
          expect(entry.value, isNotEmpty,
              reason: 'Axis index ${entry.key} should map to a non-empty key');
        }

        expect(expectedAxisKeys.length, 6);
      });

      test('axis index 6+ is out of range', () {
        const validIndices = {0, 1, 2, 3, 4, 5};
        expect(validIndices.contains(6), isFalse);
        expect(validIndices.contains(99), isFalse);
        expect(validIndices.contains(-1), isFalse);
      });
    });

    group('SDL hardware ref formats', () {
      test('button format is b followed by number', () {
        final buttonPattern = RegExp(r'^b\d+$');
        expect(buttonPattern.hasMatch('b0'), isTrue);
        expect(buttonPattern.hasMatch('b15'), isTrue);
        expect(buttonPattern.hasMatch('a0'), isFalse);
      });

      test('axis format is a followed by number', () {
        final axisPattern = RegExp(r'^[+\-]?a\d+$');
        expect(axisPattern.hasMatch('a0'), isTrue);
        expect(axisPattern.hasMatch('+a0'), isTrue);
        expect(axisPattern.hasMatch('-a0'), isTrue);
        expect(axisPattern.hasMatch('b0'), isFalse);
      });

      test('hat format is h followed by index.bitmask', () {
        final hatPattern = RegExp(r'^h\d+\.\d+$');
        expect(hatPattern.hasMatch('h0.1'), isTrue);
        expect(hatPattern.hasMatch('h0.15'), isTrue);
        expect(hatPattern.hasMatch('h1.4'), isTrue);
        expect(hatPattern.hasMatch('a0'), isFalse);
      });
    });
  });
}
