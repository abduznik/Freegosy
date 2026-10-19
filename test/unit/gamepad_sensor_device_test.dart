import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/input/gamepad_service.dart';
import 'package:freegosy/core/input/gamepad_utils.dart';
import 'package:freegosy/core/input/input_action_bus.dart';
import 'package:freegosy/providers/ui_provider.dart';
import 'package:gamepads_platform_interface/api/gamepad_controller.dart';
import 'package:gamepads_platform_interface/api/gamepad_event.dart';
import 'package:gamepads_platform_interface/gamepads_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #169: a DualSense on Linux lists its motion sensors as a second
/// /dev/input/js* device that streams axis values nonstop.
class _FakeGamepads extends GamepadsPlatformInterface {
  final events = StreamController<GamepadEvent>.broadcast();
  List<(String, String)> pads = [];

  @override
  Future<List<GamepadController>> listGamepads() async =>
      [for (final (id, name) in pads) GamepadController(id: id, name: name, plugin: this)];

  @override
  Stream<GamepadEvent> get gamepadEventsStream => events.stream;

  @override
  Stream<GamepadEvent> eventsByGamepad(String gamepadId) => const Stream.empty();
}

GamepadEvent _event(String id, KeyType type, String key, double value) =>
    GamepadEvent(gamepadId: id, timestamp: 0, type: type, key: key, value: value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isSensorDevice matches sensor and touchpad nodes, not pads', () {
    expect(GamepadUtils.isSensorDevice('DualSense Wireless Controller Motion Sensors'), isTrue);
    expect(GamepadUtils.isSensorDevice('Sony Interactive Entertainment DualSense Wireless Controller Touchpad'), isTrue);
    expect(GamepadUtils.isSensorDevice('Wireless Controller Motion Sensors'), isTrue);
    expect(GamepadUtils.isSensorDevice('DualSense Wireless Controller'), isFalse);
    expect(GamepadUtils.isSensorDevice('Xbox 360 Controller'), isFalse);
    expect(GamepadUtils.isSensorDevice(''), isFalse);
  });

  final fake = _FakeGamepads();
  GamepadsPlatformInterface.instance = fake;
  late ProviderContainer container;
  late GamepadService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fake.pads = [
      ('js0', 'DualSense Wireless Controller'),
      ('js1', 'DualSense Wireless Controller Motion Sensors'),
    ];
    container = ProviderContainer();
    service = container.read(gamepadServiceProvider);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!fake.events.hasListener) {
      if (DateTime.now().isAfter(deadline)) fail('GamepadService never listened for events');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await pumpEventQueue();
  });

  tearDown(() {
    service.dispose();
    container.dispose();
  });

  test('the sensor node is not listed as a controller', () async {
    await pumpEventQueue();
    final ids = service.getDetectedControllers().map((c) => c['id']);
    expect(ids, contains('js0'));
    expect(ids, isNot(contains('js1')));
  });

  test('a flood from the sensor node is dropped and cannot flip input mode', () async {
    await pumpEventQueue();
    final raw = <GamepadEvent>[];
    final actions = <GameAction>[];
    final rawSub = service.rawEvents.listen(raw.add);
    final actionSub = inputActionBus.stream.listen(actions.add);

    final sw = Stopwatch()..start();
    for (var i = 0; i < 20000; i++) {
      fake.events.add(_event('js1', KeyType.analog, '${i % 6}', 1000.0 + i));
    }
    await pumpEventQueue();
    sw.stop();
    // ignore: avoid_print
    print('sensor flood: 20000 events, ${raw.where((e) => e.gamepadId == 'js1').length} reached the app, ${sw.elapsedMilliseconds} ms');

    expect(raw.where((e) => e.gamepadId == 'js1'), isEmpty);
    expect(actions, isEmpty);
    expect(container.read(inputModeProvider), isNot(InputMode.gamepad));

    await rawSub.cancel();
    await actionSub.cancel();
  });

  test('the real pad still works while the sensor node is noisy', () async {
    await pumpEventQueue();
    final raw = <GamepadEvent>[];
    final sub = service.rawEvents.listen(raw.add);
    for (var i = 0; i < 1000; i++) {
      fake.events.add(_event('js1', KeyType.analog, '2', 1300.0 + i));
    }
    fake.events.add(_event('js0', KeyType.button, '0', 1));
    fake.events.add(_event('js0', KeyType.button, '0', 0));
    await pumpEventQueue();
    expect(raw.map((e) => e.gamepadId).toSet(), {'js0'});
    expect(container.read(inputModeProvider), InputMode.gamepad);
    await sub.cancel();
  });
}
