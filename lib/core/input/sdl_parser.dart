import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'gamepad_service.dart';

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
            // Translate SDL hardware ref (e.g. b0) to package key (e.g. button_0)
            final packageKey = _translateToPackageKey(hardwareRef);
            if (packageKey != null) {
              mapping[packageKey] = action;
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
    // Try exact match or partial match
    for (final entry in _cache.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }
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
      default: return null;
    }
  }

  static String? _translateToPackageKey(String hardwareRef) {
    // SDL: b0, b1... -> Package: button_0, button_1...
    if (hardwareRef.startsWith('b')) {
      return 'button_${hardwareRef.substring(1)}';
    }
    // SDL: a0, a1... -> Package: l.joystick - xAxis, l.joystick - yAxis (Switch mode)
    // or left_x, left_y (Generic)
    // This is the tricky part - we'll map both to be safe
    if (hardwareRef == 'a0') return 'left_x';
    if (hardwareRef == 'a1') return 'left_y';
    if (hardwareRef == 'a2') return 'right_x';
    if (hardwareRef == 'a3') return 'right_y';
    
    // Fallback for Switch-style names seen in logs
    if (hardwareRef == 'a0') return 'l.joystick - xAxis';
    if (hardwareRef == 'a1') return 'l.joystick - yAxis';

    return null;
  }
}
