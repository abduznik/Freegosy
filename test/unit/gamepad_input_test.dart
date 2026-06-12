import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freegosy/core/input/gamepad_service.dart';
import 'package:freegosy/core/input/gamepad_utils.dart';
import 'package:freegosy/core/input/custom_controller_mappings.dart';
import 'package:freegosy/core/input/sdl_parser.dart';

void main() {
  tearDown(() {
    customControllerMappings = {};
  });

  // -------------------------------------------------------------------------
  group('GamepadUtils.decodePOV', () {
    test('65535 (center) returns empty', () {
      expect(GamepadUtils.decodePOV(65535), isEmpty);
    });

    test('-1 (center) returns empty', () {
      expect(GamepadUtils.decodePOV(-1), isEmpty);
    });

    test('0° = up', () {
      expect(GamepadUtils.decodePOV(0), equals([GameAction.up]));
    });

    test('9000 (90°) = right', () {
      expect(GamepadUtils.decodePOV(9000), equals([GameAction.right]));
    });

    test('18000 (180°) = down', () {
      expect(GamepadUtils.decodePOV(18000), equals([GameAction.down]));
    });

    test('27000 (270°) = left', () {
      expect(GamepadUtils.decodePOV(27000), equals([GameAction.left]));
    });

    test('4500 (45°) = up + right diagonal', () {
      expect(GamepadUtils.decodePOV(4500), containsAll([GameAction.up, GameAction.right]));
    });

    test('13500 (135°) = down + right diagonal', () {
      expect(GamepadUtils.decodePOV(13500), containsAll([GameAction.down, GameAction.right]));
    });

    test('22500 (225°) = down + left diagonal', () {
      expect(GamepadUtils.decodePOV(22500), containsAll([GameAction.down, GameAction.left]));
    });

    test('31500 (315°) = up + left diagonal', () {
      expect(GamepadUtils.decodePOV(31500), containsAll([GameAction.up, GameAction.left]));
    });

    test('35999 (just before 360°) = up', () {
      expect(GamepadUtils.decodePOV(35999), equals([GameAction.up]));
    });
  });

  // -------------------------------------------------------------------------
  group('GamepadUtils.backendHandledActions', () {
    test('empty set → nothing handled', () {
      expect(GamepadUtils.backendHandledActions({}), isEmpty);
    });

    test('dwpov → all d-pad directions handled', () {
      final handled = GamepadUtils.backendHandledActions({'dwpov'});
      expect(handled, containsAll([
        GameAction.up, GameAction.down, GameAction.left, GameAction.right,
      ]));
    });

    test('pov0 (alternate name) → d-pad directions handled', () {
      expect(GamepadUtils.backendHandledActions({'pov0'}), contains(GameAction.up));
    });

    test('dwxpos + dwypos → axis actions handled', () {
      final handled = GamepadUtils.backendHandledActions({'dwxpos', 'dwypos'});
      expect(handled, containsAll([GameAction.horizontalAxis, GameAction.verticalAxis]));
    });

    test('regular button keys → nothing handled', () {
      expect(GamepadUtils.backendHandledActions({'button_0', 'button_1'}), isEmpty);
    });

    test('pov + buttons: only d-pad flagged, not axes', () {
      final handled = GamepadUtils.backendHandledActions({'dwpov', 'button_0'});
      expect(handled, containsAll([GameAction.up, GameAction.down]));
      expect(handled, isNot(contains(GameAction.horizontalAxis)));
    });

    test('only dwypos without dwxpos still flags axes', () {
      final handled = GamepadUtils.backendHandledActions({'dwypos'});
      expect(handled, contains(GameAction.verticalAxis));
    });
  });

  // -------------------------------------------------------------------------
  group('GamepadUtils.tokenize', () {
    test('strips noise words', () {
      final tokens = GamepadUtils.tokenize('USB HID Gamepad Controller');
      expect(tokens, isEmpty);
    });

    test('keeps meaningful words', () {
      final tokens = GamepadUtils.tokenize('Microsoft Xbox Wireless');
      expect(tokens, containsAll(['microsoft', 'xbox']));
      expect(tokens, isNot(contains('wireless')));
    });

    test('handles punctuation and special chars', () {
      final tokens = GamepadUtils.tokenize('8BitDo SN30 Pro+');
      expect(tokens, containsAll(['8bitdo', 'sn30', 'pro']));
    });

    test('single-char tokens are filtered out', () {
      final tokens = GamepadUtils.tokenize('A B C Xbox');
      expect(tokens, equals({'xbox'}));
    });

    test('empty string returns empty set', () {
      expect(GamepadUtils.tokenize(''), isEmpty);
    });

    test('duplicate words produce single token', () {
      final tokens = GamepadUtils.tokenize('Xbox Xbox');
      expect(tokens, equals({'xbox'}));
    });
  });

  // -------------------------------------------------------------------------
  group('SDLMappingParser.getMapping', () {
    test('returns null for completely unknown name', () {
      expect(SDLMappingParser.getMapping('ZZZZ Unknown Pad 9999'), isNull);
    });

    test('returns null for empty string', () {
      expect(SDLMappingParser.getMapping(''), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('Custom mapping persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('save then load round-trips single controller', () async {
      customControllerMappings = {
        'My Controller': {
          'button_0': GameAction.confirm,
          'button_1': GameAction.back,
          'dpad_up': GameAction.up,
        },
      };

      await saveCustomMappings();
      customControllerMappings = {};
      await loadCustomMappings();

      expect(customControllerMappings, contains('My Controller'));
      final m = customControllerMappings['My Controller']!;
      expect(m['button_0'], GameAction.confirm);
      expect(m['button_1'], GameAction.back);
      expect(m['dpad_up'], GameAction.up);
    });

    test('no saved data leaves map empty', () async {
      await loadCustomMappings();
      expect(customControllerMappings, isEmpty);
    });

    test('corrupt JSON resets to empty without throwing', () async {
      SharedPreferences.setMockInitialValues({
        'custom_controller_mappings_v1': 'not {{ valid json',
      });
      await expectLater(loadCustomMappings(), completes);
      expect(customControllerMappings, isEmpty);
    });

    test('unknown action name falls back to confirm', () async {
      SharedPreferences.setMockInitialValues({
        'custom_controller_mappings_v1': jsonEncode({
          'Pad': {'button_0': 'actionThatDoesNotExist'},
        }),
      });
      await loadCustomMappings();
      expect(customControllerMappings['Pad']!['button_0'], GameAction.confirm);
    });

    test('save writes correct JSON to SharedPreferences', () async {
      customControllerMappings = {
        'TestPad': {'button_5': GameAction.start},
      };
      await saveCustomMappings();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('custom_controller_mappings_v1');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['TestPad']['button_5'], 'start');
    });

    test('multiple controllers round-trip correctly', () async {
      customControllerMappings = {
        'Pad A': {'button_0': GameAction.confirm, 'button_1': GameAction.back},
        'Pad B': {'button_0': GameAction.detail, 'dpad_up': GameAction.up},
      };
      await saveCustomMappings();
      customControllerMappings = {};
      await loadCustomMappings();

      expect(customControllerMappings['Pad A']!['button_0'], GameAction.confirm);
      expect(customControllerMappings['Pad A']!['button_1'], GameAction.back);
      expect(customControllerMappings['Pad B']!['button_0'], GameAction.detail);
      expect(customControllerMappings['Pad B']!['dpad_up'], GameAction.up);
    });

    test('empty mapping saves and loads as empty', () async {
      customControllerMappings = {};
      await saveCustomMappings();
      customControllerMappings = {'Stale': {}};
      await loadCustomMappings();
      expect(customControllerMappings, isEmpty);
    });

    test('overwriting existing save with new data works', () async {
      customControllerMappings = {'Old': {'button_0': GameAction.confirm}};
      await saveCustomMappings();

      customControllerMappings = {'New': {'button_1': GameAction.back}};
      await saveCustomMappings();
      customControllerMappings = {};
      await loadCustomMappings();

      expect(customControllerMappings, isNot(contains('Old')));
      expect(customControllerMappings['New']!['button_1'], GameAction.back);
    });

    test('all GameAction values survive round-trip', () async {
      final allActions = {
        for (final a in GameAction.values) 'key_${a.name}': a,
      };
      customControllerMappings = {'AllActions': allActions};
      await saveCustomMappings();
      customControllerMappings = {};
      await loadCustomMappings();

      final loaded = customControllerMappings['AllActions']!;
      for (final a in GameAction.values) {
        expect(loaded['key_${a.name}'], a);
      }
    });
  });
}
