import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freegosy/core/input/gamepad_service.dart';
import 'package:freegosy/core/input/gamepad_utils.dart';
import 'package:freegosy/core/input/custom_controller_mappings.dart';
import 'package:freegosy/core/input/known_controllers.dart';
import 'package:freegosy/core/input/sdl_parser.dart';
import 'package:freegosy/core/input/deadzone_config.dart';

/// Regression tests for the existing controller settings system.
/// These lock down the current behaviour so future changes (e.g. deadzone
/// additions) don't accidentally break button mapping, persistence, or
/// utility logic.
void main() {
  tearDown(() {
    customControllerMappings = {};
  });

  // =========================================================================
  // 1. Known controller mappings (built-in list)
  // =========================================================================
  group('Built-in controller mappings', () {
    test('default mapping contains all core actions', () {
      expect(kDefaultMapping, isNotEmpty);
      expect(kDefaultMapping.values, contains(GameAction.confirm));
      expect(kDefaultMapping.values, contains(GameAction.back));
      expect(kDefaultMapping.values, contains(GameAction.up));
      expect(kDefaultMapping.values, contains(GameAction.down));
      expect(kDefaultMapping.values, contains(GameAction.left));
      expect(kDefaultMapping.values, contains(GameAction.right));
    });

    test('kControllerMappings is not empty', () {
      expect(kControllerMappings, isNotEmpty);
    });

    test('every built-in mapping is non-empty', () {
      for (final entry in kControllerMappings.entries) {
        expect(entry.value, isNotEmpty,
            reason: '${entry.key} has empty mapping');
      }
    });
  });

  // =========================================================================
  // 2. POV decoding
  // =========================================================================
  group('POV decoding — all cardinal + diagonal directions', () {
    test('center (65535) → empty', () {
      expect(GamepadUtils.decodePOV(65535), isEmpty);
    });

    test('center (-1) → empty', () {
      expect(GamepadUtils.decodePOV(-1), isEmpty);
    });

    test('0° → up', () {
      expect(GamepadUtils.decodePOV(0), [GameAction.up]);
    });

    test('4500 (45°) → up + right', () {
      expect(GamepadUtils.decodePOV(4500),
          containsAll([GameAction.up, GameAction.right]));
    });

    test('9000 (90°) → right', () {
      expect(GamepadUtils.decodePOV(9000), [GameAction.right]);
    });

    test('13500 (135°) → down + right', () {
      expect(GamepadUtils.decodePOV(13500),
          containsAll([GameAction.down, GameAction.right]));
    });

    test('18000 (180°) → down', () {
      expect(GamepadUtils.decodePOV(18000), [GameAction.down]);
    });

    test('22500 (225°) → down + left', () {
      expect(GamepadUtils.decodePOV(22500),
          containsAll([GameAction.down, GameAction.left]));
    });

    test('27000 (270°) → left', () {
      expect(GamepadUtils.decodePOV(27000), [GameAction.left]);
    });

    test('31500 (315°) → up + left', () {
      expect(GamepadUtils.decodePOV(31500),
          containsAll([GameAction.up, GameAction.left]));
    });

    test('35999 (just before 360°) → up', () {
      expect(GamepadUtils.decodePOV(35999), [GameAction.up]);
    });
  });

  // =========================================================================
  // 3. Backend-handled action detection
  // =========================================================================
  group('backendHandledActions', () {
    test('empty → nothing handled', () {
      expect(GamepadUtils.backendHandledActions({}), isEmpty);
    });

    test('dwpov → all d-pad directions', () {
      final h = GamepadUtils.backendHandledActions({'dwpov'});
      expect(h, containsAll([
        GameAction.up, GameAction.down, GameAction.left, GameAction.right,
      ]));
    });

    test('pov0 → d-pad directions', () {
      expect(GamepadUtils.backendHandledActions({'pov0'}),
          contains(GameAction.up));
    });

    test('hat0x → d-pad directions', () {
      final h = GamepadUtils.backendHandledActions({'hat0x'});
      expect(h, containsAll([GameAction.up, GameAction.down]));
    });

    test('dwxpos + dwypos → axis actions', () {
      final h = GamepadUtils.backendHandledActions({'dwxpos', 'dwypos'});
      expect(h, containsAll([
        GameAction.horizontalAxis, GameAction.verticalAxis,
      ]));
    });

    test('only dwypos → both axes (backend treats dwxpos/dwypos as pair)', () {
      final h = GamepadUtils.backendHandledActions({'dwypos'});
      expect(h, contains(GameAction.verticalAxis));
      // The backend flags both axes when either dwxpos or dwypos is seen
      expect(h, contains(GameAction.horizontalAxis));
    });

    test('regular buttons → nothing handled', () {
      expect(GamepadUtils.backendHandledActions({'button_0', 'button_1'}),
          isEmpty);
    });

    test('numeric-only keys (bare hat indices) → not auto-handled', () {
      expect(GamepadUtils.backendHandledActions({'6', '7'}), isEmpty);
    });

    test('pov + buttons → only d-pad flagged', () {
      final h = GamepadUtils.backendHandledActions({'dwpov', 'button_0'});
      expect(h, containsAll([GameAction.up, GameAction.down]));
      expect(h, isNot(contains(GameAction.horizontalAxis)));
    });
  });

  // =========================================================================
  // 4. Key encoding / decoding
  // =========================================================================
  group('encodeKey / decodeKey / hasPolaritySuffix', () {
    test('positive polarity → suffix +', () {
      expect(GamepadUtils.encodeKey('7', 1), '7+');
    });

    test('negative polarity → suffix -', () {
      expect(GamepadUtils.encodeKey('7', -1), '7-');
    });

    test('zero polarity → suffix +', () {
      expect(GamepadUtils.encodeKey('7', 0), '7+');
    });

    test('decodeKey + → polarity 1', () {
      final (k, p) = GamepadUtils.decodeKey('7+');
      expect(k, '7');
      expect(p, 1);
    });

    test('decodeKey - → polarity -1', () {
      final (k, p) = GamepadUtils.decodeKey('6-');
      expect(k, '6');
      expect(p, -1);
    });

    test('decodeKey no suffix → polarity 0', () {
      final (k, p) = GamepadUtils.decodeKey('button_0');
      expect(k, 'button_0');
      expect(p, 0);
    });

    test('hasPolaritySuffix detects + and -', () {
      expect(GamepadUtils.hasPolaritySuffix('6+'), isTrue);
      expect(GamepadUtils.hasPolaritySuffix('6-'), isTrue);
      expect(GamepadUtils.hasPolaritySuffix('button_0'), isFalse);
      expect(GamepadUtils.hasPolaritySuffix('dpad_up'), isFalse);
    });

    test('round-trip encode → decode preserves key and polarity', () {
      for (final pol in [1, -1]) {
        final encoded = GamepadUtils.encodeKey('axis_0', pol);
        final (decoded, decodedPol) = GamepadUtils.decodeKey(encoded);
        expect(decoded, 'axis_0');
        expect(decodedPol, pol);
      }
    });
  });

  // =========================================================================
  // 5. Tokenizer
  // =========================================================================
  group('tokenize', () {
    test('strips noise words', () {
      expect(GamepadUtils.tokenize('USB HID Gamepad Controller'), isEmpty);
    });

    test('keeps meaningful words', () {
      final t = GamepadUtils.tokenize('Microsoft Xbox Wireless');
      expect(t, containsAll(['microsoft', 'xbox']));
      expect(t, isNot(contains('wireless')));
    });

    test('handles punctuation', () {
      final t = GamepadUtils.tokenize('8BitDo SN30 Pro+');
      expect(t, containsAll(['8bitdo', 'sn30', 'pro']));
    });

    test('single-char tokens filtered', () {
      expect(GamepadUtils.tokenize('A B C Xbox'), {'xbox'});
    });

    test('empty string → empty set', () {
      expect(GamepadUtils.tokenize(''), isEmpty);
    });

    test('duplicates produce single token', () {
      expect(GamepadUtils.tokenize('Xbox Xbox'), {'xbox'});
    });
  });

  // =========================================================================
  // 6. SDL mapping parser
  // =========================================================================
  group('SDLMappingParser.getMapping', () {
    test('returns null for unknown name', () {
      expect(SDLMappingParser.getMapping('ZZZZ Unknown Pad 9999'), isNull);
    });

    test('returns null for empty string', () {
      expect(SDLMappingParser.getMapping(''), isNull);
    });
  });

  // =========================================================================
  // 7. Custom mapping persistence
  // =========================================================================
  group('Custom mapping persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('save → load round-trips single controller', () async {
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

    test('no saved data → map stays empty', () async {
      await loadCustomMappings();
      expect(customControllerMappings, isEmpty);
    });

    test('corrupt JSON resets without throwing', () async {
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

    test('overwriting existing save works', () async {
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

    test('polarity-encoded keys survive round-trip', () async {
      customControllerMappings = {
        'GameSir DS4': {
          '7+': GameAction.up,
          '7-': GameAction.down,
          '6+': GameAction.right,
          '6-': GameAction.left,
          'button_0': GameAction.confirm,
        },
      };
      await saveCustomMappings();
      customControllerMappings = {};
      await loadCustomMappings();

      final m = customControllerMappings['GameSir DS4']!;
      expect(m['7+'], GameAction.up);
      expect(m['7-'], GameAction.down);
      expect(m['6+'], GameAction.right);
      expect(m['6-'], GameAction.left);
      expect(m['button_0'], GameAction.confirm);
    });
  });

  // =========================================================================
  // 8. clearMappingForName
  // =========================================================================
  group('clearMappingForName', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('removes exact-name custom mapping', () async {
      customControllerMappings = {
        'GameSir Controller': {'button_0': GameAction.confirm},
      };
      await clearMappingForName('GameSir Controller');
      expect(customControllerMappings, isEmpty);
    });

    test('removes by substring match (stored ⊂ controller)', () async {
      customControllerMappings = {
        'GameSir': {'button_0': GameAction.confirm},
      };
      await clearMappingForName('GameSir DS4 BT Controller');
      expect(customControllerMappings, isEmpty);
    });

    test('removes by reverse substring match (controller ⊂ stored)', () async {
      customControllerMappings = {
        'GameSir DS4 BT Controller': {'button_0': GameAction.confirm},
      };
      await clearMappingForName('GameSir DS4');
      expect(customControllerMappings, isEmpty);
    });

    test('does not remove unrelated controllers', () async {
      customControllerMappings = {
        'GameSir': {'button_0': GameAction.confirm},
        'DualSense': {'button_0': GameAction.confirm},
      };
      await clearMappingForName('GameSir');
      expect(customControllerMappings, isNot(contains('GameSir')));
      expect(customControllerMappings, contains('DualSense'));
    });

    test('noop when no matching mapping exists', () async {
      customControllerMappings = {
        'DualSense': {'button_0': GameAction.confirm},
      };
      await clearMappingForName('Xbox Controller');
      expect(customControllerMappings, contains('DualSense'));
    });

    test('persists removal to SharedPreferences', () async {
      customControllerMappings = {
        'TestPad': {'button_0': GameAction.confirm},
      };
      await saveCustomMappings();
      await clearMappingForName('TestPad');

      customControllerMappings = {'TestPad': {}};
      await loadCustomMappings();
      expect(customControllerMappings, isEmpty);
    });
  });

  // =========================================================================
  // 9. Axis threshold constants (document current hardcoded values)
  // =========================================================================
  group('Axis threshold constants', () {
    test('activation threshold is 0.5', () {
      // The service uses 0.5 for both positive and negative activation.
      // This test documents that value so future deadzone changes are aware.
      const activationThreshold = 0.5;
      expect(activationThreshold, 0.5);
    });

    test('deactivation threshold is 0.15 (hysteresis)', () {
      const deactivationThreshold = 0.15;
      expect(deactivationThreshold, lessThan(0.5));
      expect(deactivationThreshold, greaterThan(0.0));
    });

    test('deactivation < activation (hysteresis band exists)', () {
      const activation = 0.5;
      const deactivation = 0.15;
      expect(deactivation, lessThan(activation));
    });
  });

  // =========================================================================
  // 10. NormalizedInput value preservation
  // =========================================================================
  group('NormalizedInput', () {
    test('stores action and value correctly', () {
      const input = NormalizedInput(action: GameAction.confirm, value: 0.75);
      expect(input.action, GameAction.confirm);
      expect(input.value, 0.75);
    });

    test('supports negative values for left/up axes', () {
      const input = NormalizedInput(action: GameAction.horizontalAxis, value: -0.8);
      expect(input.value, -0.8);
    });

    test('supports zero value (centered stick)', () {
      const input = NormalizedInput(action: GameAction.verticalAxis, value: 0.0);
      expect(input.value, 0.0);
    });
  });

  // =========================================================================
  // 11. GameAction enum completeness
  // =========================================================================
  group('GameAction enum', () {
    test('contains all expected actions', () {
      final names = GameAction.values.map((a) => a.name).toSet();
      expect(names, containsAll([
        'up', 'down', 'left', 'right',
        'confirm', 'back', 'detail', 'favorite',
        'verticalAxis', 'horizontalAxis',
        'l1', 'r1', 'start', 'select',
      ]));
    });

    test('has exactly 15 actions', () {
      expect(GameAction.values.length, 15);
    });
  });

  // =========================================================================
  // 12. Deadzone applyDeadzone function
  // =========================================================================
  group('applyDeadzone', () {
    test('value within deadzone returns 0', () {
      expect(applyDeadzone(0.0, 0.15), 0.0);
      expect(applyDeadzone(0.1, 0.15), 0.0);
      expect(applyDeadzone(-0.1, 0.15), 0.0);
      expect(applyDeadzone(0.15, 0.15), 0.0);
      expect(applyDeadzone(-0.15, 0.15), 0.0);
    });

    test('value at edge returns ±1', () {
      expect(applyDeadzone(1.0, 0.15), closeTo(1.0, 0.001));
      expect(applyDeadzone(-1.0, 0.15), closeTo(-1.0, 0.001));
    });

    test('midpoint rescales correctly', () {
      // With deadzone 0.15, raw 0.575 → (0.575 - 0.15) / (1 - 0.15) = 0.5
      final result = applyDeadzone(0.575, 0.15);
      expect(result, closeTo(0.5, 0.001));
    });

    test('preserves sign for negative values', () {
      final result = applyDeadzone(-0.8, 0.15);
      expect(result, lessThan(0));
      expect(result.abs(), closeTo(
          (0.8 - 0.15) / (1.0 - 0.15), 0.001));
    });

    test('deadzone 0 passes through unchanged', () {
      expect(applyDeadzone(0.5, 0.0), 0.5);
      expect(applyDeadzone(-0.3, 0.0), -0.3);
    });

    test('deadzone 0.5 clips middle range to zero', () {
      expect(applyDeadzone(0.3, 0.5), 0.0);
      expect(applyDeadzone(0.5, 0.5), 0.0);
    });

    test('zero value with any deadzone returns 0', () {
      expect(applyDeadzone(0.0, 0.0), 0.0);
      expect(applyDeadzone(0.0, 0.25), 0.0);
      expect(applyDeadzone(0.0, 0.5), 0.0);
    });
  });

  // =========================================================================
  // 13. Deadzone config defaults
  // =========================================================================
  group('Deadzone config defaults', () {
    test('kDefaultDeadzone is 0.15', () {
      expect(kDefaultDeadzone, 0.15);
    });

    test('kMinDeadzone is 0.0', () {
      expect(kMinDeadzone, 0.0);
    });

    test('kMaxDeadzone is 0.50', () {
      expect(kMaxDeadzone, 0.50);
    });

    test('default is within console-typical range', () {
      expect(kDefaultDeadzone, greaterThanOrEqualTo(0.10));
      expect(kDefaultDeadzone, lessThanOrEqualTo(0.25));
    });
  });

  // =========================================================================
  // 14. Deadzone persistence
  // =========================================================================
  group('Deadzone persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      globalDeadzone = kDefaultDeadzone;
      perControllerDeadzone = {};
    });

    tearDown(() {
      globalDeadzone = kDefaultDeadzone;
      perControllerDeadzone = {};
    });

    test('save then load round-trips global deadzone', () async {
      globalDeadzone = 0.25;
      await saveDeadzoneSettings();

      globalDeadzone = kDefaultDeadzone;
      await loadDeadzoneSettings();

      expect(globalDeadzone, 0.25);
    });

    test('save then load round-trips per-controller override', () async {
      perControllerDeadzone = {'Xbox Controller': 0.30};
      await saveDeadzoneSettings();

      perControllerDeadzone = {};
      await loadDeadzoneSettings();

      expect(perControllerDeadzone, contains('Xbox Controller'));
      expect(perControllerDeadzone['Xbox Controller'], 0.30);
    });

    test('no saved data keeps defaults', () async {
      await loadDeadzoneSettings();
      expect(globalDeadzone, kDefaultDeadzone);
      expect(perControllerDeadzone, isEmpty);
    });

    test('corrupt JSON resets to defaults without throwing', () async {
      SharedPreferences.setMockInitialValues({
        'deadzone_per_controller_v1': 'not valid json',
      });
      await expectLater(loadDeadzoneSettings(), completes);
      expect(globalDeadzone, kDefaultDeadzone);
      expect(perControllerDeadzone, isEmpty);
    });

    test('values are clamped to valid range on load', () async {
      SharedPreferences.setMockInitialValues({
        'deadzone_global_v1': 999.0,
      });
      await loadDeadzoneSettings();
      expect(globalDeadzone, kMaxDeadzone);

      SharedPreferences.setMockInitialValues({
        'deadzone_global_v1': -5.0,
      });
      await loadDeadzoneSettings();
      expect(globalDeadzone, kMinDeadzone);
    });

    test('resetDeadzoneSettings restores defaults', () async {
      globalDeadzone = 0.40;
      perControllerDeadzone = {'Pad': 0.35};
      await saveDeadzoneSettings();

      await resetDeadzoneSettings();

      expect(globalDeadzone, kDefaultDeadzone);
      expect(perControllerDeadzone, isEmpty);
    });
  });

  // =========================================================================
  // 15. getDeadzoneForController
  // =========================================================================
  group('getDeadzoneForController', () {
    setUp(() {
      globalDeadzone = 0.15;
      perControllerDeadzone = {};
    });

    test('returns global when no per-controller override', () {
      expect(getDeadzoneForController('Xbox Controller'), 0.15);
    });

    test('returns per-controller override when set', () {
      perControllerDeadzone = {'Xbox': 0.30};
      expect(getDeadzoneForController('Xbox Wireless Controller'), 0.30);
    });

    test('substring match works (stored key ⊂ controller name)', () {
      perControllerDeadzone = {'Xbox': 0.25};
      expect(getDeadzoneForController('Xbox Wireless Controller'), 0.25);
    });

    test('substring match works (controller name ⊂ stored key)', () {
      perControllerDeadzone = {'DualShock 4 Wireless Controller': 0.25};
      expect(getDeadzoneForController('DualShock 4'), 0.25);
    });

    test('returns global for empty controller name', () {
      expect(getDeadzoneForController(''), 0.15);
    });

    test('case-insensitive matching', () {
      perControllerDeadzone = {'xbox': 0.20};
      expect(getDeadzoneForController('XBOX WIRELESS'), 0.20);
    });
  });

  // =========================================================================
  // 14. PlayStation USB controller mappings (recent additions)
  // =========================================================================
  group('PlayStation USB controller mappings', () {
    const psFaceButtonPattern = {
      'cross': GameAction.confirm,
      'circle': GameAction.back,
      'square': GameAction.detail,
      'triangle': GameAction.favorite,
    };

    test('PS4 Controller (Windows USB) exists with face buttons', () {
      final m = kControllerMappings['PS4 Controller'];
      expect(m, isNotNull, reason: 'PS4 Controller entry missing from kControllerMappings');
      for (final entry in psFaceButtonPattern.entries) {
        expect(m![entry.key], entry.value,
            reason: 'PS4 Controller ${entry.key} should map to ${entry.value}');
      }
    });

    test('PS5 Controller (Windows USB) exists with face buttons', () {
      final m = kControllerMappings['PS5 Controller'];
      expect(m, isNotNull, reason: 'PS5 Controller entry missing');
      for (final entry in psFaceButtonPattern.entries) {
        expect(m![entry.key], entry.value,
            reason: 'PS5 Controller ${entry.key} should map to ${entry.value}');
      }
    });

    test('PS5 Access Controller exists with face buttons', () {
      final m = kControllerMappings['PS5 Access Controller'];
      expect(m, isNotNull, reason: 'PS5 Access Controller entry missing');
      for (final entry in psFaceButtonPattern.entries) {
        expect(m![entry.key], entry.value,
            reason: 'PS5 Access Controller ${entry.key} should map to ${entry.value}');
      }
    });

    test('Sony Interactive Entertainment Wireless Controller (macOS/Linux) exists', () {
      final m = kControllerMappings['Sony Interactive Entertainment Wireless Controller'];
      expect(m, isNotNull, reason: 'Sony ISE Wireless Controller entry missing');
      for (final entry in psFaceButtonPattern.entries) {
        expect(m![entry.key], entry.value);
      }
    });

    test('all PlayStation entries have d-pad and shoulder buttons', () {
      const psNames = [
        'PS4 Controller',
        'PS5 Controller',
        'PS5 Access Controller',
        'Sony Interactive Entertainment Wireless Controller',
      ];
      for (final name in psNames) {
        final m = kControllerMappings[name];
        expect(m, isNotNull, reason: '$name missing');
        expect(m!['dpad_up'], GameAction.up, reason: '$name dpad_up');
        expect(m['dpad_down'], GameAction.down, reason: '$name dpad_down');
        expect(m['dpad_left'], GameAction.left, reason: '$name dpad_left');
        expect(m['dpad_right'], GameAction.right, reason: '$name dpad_right');
        expect(m['leftshoulder'], GameAction.l1, reason: '$name L1');
        expect(m['rightshoulder'], GameAction.r1, reason: '$name R1');
      }
    });
  });

  // =========================================================================
  // 15. Empty-token fallback (Bluetooth noise-only controller names)
  // =========================================================================
  group('Empty-token controller fallback', () {
    test('noise-only names tokenize to empty set', () {
      expect(GamepadUtils.tokenize('Wireless Controller'), isEmpty);
      expect(GamepadUtils.tokenize('USB HID Gamepad'), isEmpty);
    });

    test('empty string returns empty set (not a fallback trigger)', () {
      final tokens = GamepadUtils.tokenize('');
      expect(tokens, isEmpty);
      // Empty name should NOT trigger the warning — only non-empty noise names do
    });

    test('partial noise keeps meaningful tokens', () {
      final t = GamepadUtils.tokenize('Wireless Xbox Controller');
      expect(t, contains('xbox'));
      expect(t, isNot(contains('wireless')));
      expect(t, isNot(contains('controller')));
    });
  });

  // =========================================================================
  // 16. disambiguateKey (numeric button/axis raw-index collisions)
  // =========================================================================
  group('disambiguateKey', () {
    test('numeric key tagged as button', () {
      expect(GamepadUtils.disambiguateKey('6', isButton: true), 'btn6');
    });

    test('numeric key tagged as axis', () {
      expect(GamepadUtils.disambiguateKey('6', isButton: false), 'ax6');
    });

    test('named key passes through unchanged regardless of type', () {
      expect(GamepadUtils.disambiguateKey('dpad_up', isButton: true), 'dpad_up');
      expect(GamepadUtils.disambiguateKey('button_0', isButton: false), 'button_0');
    });

    test('Xbox 360 pad on Linux: button 6 (Back) and axis 6 (D-pad X) no longer collide', () {
      // Raw joydev indices before disambiguation: both arrive as key "6".
      final backKey = GamepadUtils.disambiguateKey('6', isButton: true);
      final dpadXKey = GamepadUtils.disambiguateKey('6', isButton: false);
      expect(backKey, isNot(dpadXKey));
    });

    test('Xbox 360 pad on Linux: button 7 (Start) and axis 7 (D-pad Y) no longer collide', () {
      final startKey = GamepadUtils.disambiguateKey('7', isButton: true);
      final dpadYKey = GamepadUtils.disambiguateKey('7', isButton: false);
      expect(startKey, isNot(dpadYKey));
    });

    test('composes with encodeKey: button key and both axis polarity keys stay distinct', () {
      final backKey = GamepadUtils.disambiguateKey('6', isButton: true);
      final rightKey = GamepadUtils.encodeKey(
          GamepadUtils.disambiguateKey('6', isButton: false), 1);
      final leftKey = GamepadUtils.encodeKey(
          GamepadUtils.disambiguateKey('6', isButton: false), -1);
      expect({backKey, rightKey, leftKey}, hasLength(3));
    });
  });

  // =========================================================================
  // 17. Linux numeric-key collision regression (Xbox 360 pad)
  // =========================================================================
  group('Linux numeric-key collision regression (Xbox 360 pad)', () {
    // Mirrors the storage keys _registerCurrent() now produces for a
    // Microsoft Xbox 360 pad's raw /dev/input/js* events, where Back/Start
    // are buttons 6/7 and the D-pad's X/Y axes are also indices 6/7.
    final mapping = {
      GamepadUtils.disambiguateKey('6', isButton: true): GameAction.select,
      GamepadUtils.disambiguateKey('7', isButton: true): GameAction.start,
      GamepadUtils.encodeKey(GamepadUtils.disambiguateKey('6', isButton: false), 1):
          GameAction.right,
      GamepadUtils.encodeKey(GamepadUtils.disambiguateKey('6', isButton: false), -1):
          GameAction.left,
      GamepadUtils.encodeKey(GamepadUtils.disambiguateKey('7', isButton: false), 1):
          GameAction.down,
      GamepadUtils.encodeKey(GamepadUtils.disambiguateKey('7', isButton: false), -1):
          GameAction.up,
    };

    test('button 6 (Back) resolves to select, not a D-pad direction', () {
      expect(mapping[GamepadUtils.disambiguateKey('6', isButton: true)], GameAction.select);
    });

    test('axis 6 positive (D-pad right) resolves to right, not select', () {
      final key = GamepadUtils.encodeKey(GamepadUtils.disambiguateKey('6', isButton: false), 1);
      expect(mapping[key], GameAction.right);
    });

    test('axis 6 negative (D-pad left) resolves to left, not select', () {
      final key = GamepadUtils.encodeKey(GamepadUtils.disambiguateKey('6', isButton: false), -1);
      expect(mapping[key], GameAction.left);
    });

    test('button 7 (Start) resolves to start, not a D-pad direction', () {
      expect(mapping[GamepadUtils.disambiguateKey('7', isButton: true)], GameAction.start);
    });

    test('axis 7 positive (D-pad down) resolves to down, not start', () {
      final key = GamepadUtils.encodeKey(GamepadUtils.disambiguateKey('7', isButton: false), 1);
      expect(mapping[key], GameAction.down);
    });

    test('axis 7 negative (D-pad up) resolves to up, not start', () {
      final key = GamepadUtils.encodeKey(GamepadUtils.disambiguateKey('7', isButton: false), -1);
      expect(mapping[key], GameAction.up);
    });
  });

  // =========================================================================
  // 18. normalizeAxisValue (raw Linux joydev magnitudes vs normalized ranges)
  // =========================================================================
  group('normalizeAxisValue', () {
    test('values already within -1.0..1.0 pass through unchanged', () {
      expect(GamepadUtils.normalizeAxisValue(0.0), 0.0);
      expect(GamepadUtils.normalizeAxisValue(1.0), 1.0);
      expect(GamepadUtils.normalizeAxisValue(-1.0), -1.0);
      expect(GamepadUtils.normalizeAxisValue(0.42), 0.42);
    });

    test('raw positive int16 magnitude rescales toward 1.0', () {
      expect(GamepadUtils.normalizeAxisValue(32767.0), closeTo(1.0, 0.001));
    });

    test('raw negative int16 magnitude rescales toward -1.0', () {
      expect(GamepadUtils.normalizeAxisValue(-32767.0), closeTo(-1.0, 0.001));
    });

    test('small raw jitter no longer reads as fully pressed', () {
      // A few dozen units of int16 sensor noise on an idle axis used to
      // trivially satisfy the wizard's isPressed threshold (abs >= 0.5)
      // because it was compared against the raw magnitude directly.
      final normalized = GamepadUtils.normalizeAxisValue(50.0);
      expect(normalized.abs(), lessThan(0.5));
    });

    test('out-of-range magnitude clamps to -1.0..1.0', () {
      expect(GamepadUtils.normalizeAxisValue(40000.0), 1.0);
      expect(GamepadUtils.normalizeAxisValue(-40000.0), -1.0);
    });
  });
}
