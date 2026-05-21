import 'gamepad_service.dart';

/// Database of hardware-specific mappings for various controllers and modes.
/// Following the SDL2 gamecontrollerdb pattern.
const Map<String, Map<String, GameAction>> kControllerMappings = {
  // 8BitDo Micro - Switch mode (macOS IOKit)
  '8BitDo Micro': {
    'a.circle': GameAction.confirm,
    'b.circle': GameAction.back,
    'x.circle': GameAction.detail,
    'y.circle': GameAction.favorite,
    'l.joystick - yAxis': GameAction.verticalAxis,
    'l.joystick - xAxis': GameAction.horizontalAxis,
  },

  // 8BitDo Micro - D mode (Generic D-Input)
  '8BitDo Micro gamepad': {
    'button_0': GameAction.confirm,
    'button_1': GameAction.back,
    'button_2': GameAction.detail,
    'button_3': GameAction.favorite,
    'dpad_up': GameAction.up,
    'dpad_down': GameAction.down,
    'dpad_left': GameAction.left,
    'dpad_right': GameAction.right,
  },

  // Xbox Controllers (Windows XInput / Generic Bluetooth)
  'Xbox': {
    'button_0': GameAction.confirm,
    'button_1': GameAction.back,
    'button_2': GameAction.detail,
    'button_3': GameAction.favorite,
    'a': GameAction.confirm,
    'b': GameAction.back,
    'x': GameAction.detail,
    'y': GameAction.favorite,
  },

  // DualSense / DualShock
  'DualSense': {
    'cross': GameAction.confirm,
    'circle': GameAction.back,
    'square': GameAction.detail,
    'triangle': GameAction.favorite,
  },

  // macOS Pro Controller / Switch-style Descriptive Strings
  'Pro Controller': {
    'a.circle': GameAction.confirm,
    'b.circle': GameAction.back,
    'x.circle': GameAction.detail,
    'y.circle': GameAction.favorite,
    'l.joystick - xAxis': GameAction.horizontalAxis,
    'l.joystick - yAxis': GameAction.verticalAxis,
    'dpad - xAxis': GameAction.horizontalAxis,
    'dpad - yAxis': GameAction.verticalAxis,
    'buttonMenu': GameAction.start,
    'buttonOptions': GameAction.select,
    'l.rectangle.roundedbottom': GameAction.l1,
    'r.rectangle.roundedbottom': GameAction.r1,
    'zl.rectangle.roundedtop': GameAction.l2,
    'zr.rectangle.roundedtop': GameAction.r2,
  },
};

/// Fallback for unknown controllers - covers most XInput-style layouts
const Map<String, GameAction> kDefaultMapping = {
  'button_0': GameAction.confirm,
  'button_1': GameAction.back,
  'button_2': GameAction.detail,
  'button_3': GameAction.favorite,
  'a': GameAction.confirm,
  'b': GameAction.back,
  'x': GameAction.detail,
  'y': GameAction.favorite,
  
  // Mac/Switch Fallbacks
  'a.circle': GameAction.confirm,
  'b.circle': GameAction.back,
  'x.circle': GameAction.detail,
  'y.circle': GameAction.favorite,
  'l.joystick - xAxis': GameAction.horizontalAxis,
  'l.joystick - yAxis': GameAction.verticalAxis,
  'dpad - xAxis': GameAction.horizontalAxis,
  'dpad - yAxis': GameAction.verticalAxis,
  'buttonMenu': GameAction.start,
  'buttonOptions': GameAction.select,
  'l.rectangle.roundedbottom': GameAction.l1,
  'r.rectangle.roundedbottom': GameAction.r1,
  'zl.rectangle.roundedtop': GameAction.l2,
  'zr.rectangle.roundedtop': GameAction.r2,

  'dpad_up': GameAction.up,
  'dpad_down': GameAction.down,
  'dpad_left': GameAction.left,
  'dpad_right': GameAction.right,
  'button_11': GameAction.up,
  'button_12': GameAction.down,
  'button_13': GameAction.left,
  'button_14': GameAction.right,
};
