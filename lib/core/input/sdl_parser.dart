import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'gamepad_service.dart';
import 'gamepad_utils.dart';

class SDLMappingParser {
  static final Map<String, Map<String, GameAction>> _cache = {};

  /// Loads and parses the SDL2 gamecontrollerdb.txt asset.
  static Future<void> loadDatabase() async {
    try {
      final data = await rootBundle.loadString('thirdparty/gamecontrollerdb.txt');
      final lines = data.split('\n');

      for (var line in lines) {
        if (line.startsWith('#') || line.trim().isEmpty) continue;

        final parts = line.split(',');
        if (parts.length < 3) continue;

        final name = parts[1].trim();
        final mapping = <String, GameAction>{};

        for (var i = 2; i < parts.length; i++) {
          final entry = parts[i].split(':');
          if (entry.length != 2) continue;

          final sdlKey = entry[0].trim();
          final hardwareRef = entry[1].trim();

          final action = _mapSDLKeyToAction(sdlKey);
          if (action != null) {
            // Translate SDL hardware ref (e.g. b0, h0.1, a0, a0+) to package
            // key (e.g. button_0, dpad_up, left_x, left_x+).
            final packageKeys = _translateToPackageKeys(hardwareRef, action);
            for (final pk in packageKeys) {
              mapping[pk] = action;
            }
          }
        }
        _cache[name.toLowerCase()] = mapping;
      }
    } catch (e) {
      debugPrint('🎮 SDL Parser Error: $e');
    }
  }

  static Map<String, GameAction>? getMapping(String name) {
    final lower = name.toLowerCase();

    // 1. Exact match
    if (_cache.containsKey(lower)) return _cache[lower];

    // 2. Substring match (controller name contains db entry, or db entry contains controller name)
    for (final entry in _cache.entries) {
      if (lower.contains(entry.key) || entry.key.contains(lower)) {
        return entry.value;
      }
    }

    // 3. Fuzzy: score by how many meaningful tokens overlap
    final inputTokens = GamepadUtils.tokenize(lower);
    if (inputTokens.isEmpty) return null;

    String? bestKey;
    int bestScore = 0;

    for (final entry in _cache.entries) {
      final dbTokens = GamepadUtils.tokenize(entry.key);
      final shared = inputTokens.intersection(dbTokens).length;
      // Require at least 2 shared tokens, or all input tokens matched
      if (shared >= 2 || (shared >= 1 && shared == inputTokens.length)) {
        if (shared > bestScore) {
          bestScore = shared;
          bestKey = entry.key;
        }
      }
    }

    if (bestKey != null) return _cache[bestKey];
    return null;
  }

  static GameAction? _mapSDLKeyToAction(String sdlKey) {
    switch (sdlKey) {
      case 'a': return GameAction.confirm;
      case 'b': return GameAction.back;
      case 'x': return GameAction.detail;
      case 'y': return GameAction.favorite;
      case 'dpup': return GameAction.up;
      case 'dpdown': return GameAction.down;
      case 'dpleft': return GameAction.left;
      case 'dpright': return GameAction.right;
      case 'leftx': return GameAction.horizontalAxis;
      case 'lefty': return GameAction.verticalAxis;
      case 'leftshoulder': return GameAction.l1;
      case 'rightshoulder': return GameAction.r1;
      case 'start': return GameAction.start;
      case 'back': return GameAction.select;
      case 'guide': return GameAction.start;
      default: return null;
    }
  }

  /// Translates an SDL hardware reference into one or more package key strings.
  ///
  /// SDL hardware ref formats:
  ///   b0, b1 ...        — button index
  ///   a0, a1 ...        — axis index (full axis, both directions)
  ///   +a0, -a0 ...      — axis index with explicit direction
  ///   h0.1, h0.2,
  ///   h0.4, h0.8 ...    — hat switch (bitmask: 1=up 2=right 4=down 8=left)
  ///
  /// Hat switches map directly to named dpad_* keys because the runtime
  /// already handles `dwpov` / `pov*` angle decoding for POV-style hats.
  /// For Linux /dev/input/js* hats that arrive as numeric axis keys with
  /// polarity, the sniff wizard will capture them as "N+" / "N-" keys —
  /// those are stored verbatim and need no translation here.
  static List<String> _translateToPackageKeys(String hardwareRef, GameAction action) {
    // SDL hat switch: h<hat_index>.<bitmask>
    // Bitmask: 1=up, 2=right, 4=down, 8=left (matches SDL_HAT_* defines)
    final hatMatch = RegExp(r'^h(\d+)\.(\d+)$').firstMatch(hardwareRef);
    if (hatMatch != null) {
      final bitmask = int.tryParse(hatMatch.group(2)!) ?? 0;
      // Map SDL hat bitmask to named keys understood by the runtime
      switch (bitmask) {
        case 1: return ['dpad_up'];
        case 2: return ['dpad_right'];
        case 4: return ['dpad_down'];
        case 8: return ['dpad_left'];
        // Diagonals — return both directions
        case 3: return ['dpad_up', 'dpad_right'];
        case 6: return ['dpad_down', 'dpad_right'];
        case 12: return ['dpad_down', 'dpad_left'];
        case 9: return ['dpad_up', 'dpad_left'];
        default: return [];
      }
    }

    // Polarity-annotated axis: +a0 or -a0
    final polarAxisMatch = RegExp(r'^([+\-])a(\d+)$').firstMatch(hardwareRef);
    if (polarAxisMatch != null) {
      final sign = polarAxisMatch.group(1)!;
      final idx = int.tryParse(polarAxisMatch.group(2)!) ?? -1;
      final baseKey = _axisIndexToKey(idx);
      if (baseKey != null) {
        return ['$baseKey$sign'];
      }
      return [];
    }

    // Plain axis: a0, a1, a2, a3
    if (hardwareRef.startsWith('a')) {
      final idx = int.tryParse(hardwareRef.substring(1)) ?? -1;
      final baseKey = _axisIndexToKey(idx);
      if (baseKey != null) {
        // For axis actions (horizontalAxis / verticalAxis) we store both
        // polarity variants so the runtime can match either direction.
        if (action == GameAction.horizontalAxis || action == GameAction.verticalAxis) {
          return ['$baseKey+', '$baseKey-', baseKey];
        }
        return [baseKey];
      }
      return [];
    }

    // Button: b0, b1 ...
    if (hardwareRef.startsWith('b')) {
      final idx = hardwareRef.substring(1);
      return ['button_$idx'];
    }

    return [];
  }

  /// Maps SDL axis index to the package key name used at runtime.
  static String? _axisIndexToKey(int idx) {
    switch (idx) {
      case 0: return 'left_x';
      case 1: return 'left_y';
      case 2: return 'right_x';
      case 3: return 'right_y';
      case 4: return 'left_trigger';
      case 5: return 'right_trigger';
      default: return null;
    }
  }
}
