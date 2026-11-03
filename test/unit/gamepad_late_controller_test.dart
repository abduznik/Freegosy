import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/input/gamepad_service.dart';
import 'package:freegosy/core/input/input_action_bus.dart';
import 'package:gamepads_platform_interface/api/gamepad_controller.dart';
import 'package:gamepads_platform_interface/api/gamepad_event.dart';
import 'package:gamepads_platform_interface/gamepads_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Windows' GameInput: the start-up scan can run before the pad is listed,
/// and the pad's display name can be empty.
class _FakeGamepads extends GamepadsPlatformInterface {
  final events = StreamController<GamepadEvent>.broadcast();
  List<(String, String)> pads = [];

  @override
  Future<List<GamepadController>> listGamepads() async =>
      [for (final (id, name) in pads) GamepadController(id: id, name: name, plugin: this)];

  @override
  Stream<GamepadEvent> get gamepadEventsStream => events.stream;

  // Listed controllers subscribe here; kept off [events] so its listener is
  // only GamepadService.
  @override
  Stream<GamepadEvent> eventsByGamepad(String gamepadId) => const Stream.empty();
}

GamepadEvent _button(String key, double value) =>
    GamepadEvent(gamepadId: 'pad1', timestamp: 0, type: KeyType.button, key: key, value: value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The gamepads package keeps the platform it first saw, so one fake for all.
  final fake = _FakeGamepads();
  GamepadsPlatformInterface.instance = fake;
  late ProviderContainer container;
  late GamepadService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fake.pads = [];
    container = ProviderContainer();
    service = container.read(gamepadServiceProvider);
    // initialize() loads the SDL database from assets (real I/O, slow on CI)
    // before it listens; events sent before that are dropped.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!fake.events.hasListener) {
      if (DateTime.now().isAfter(deadline)) fail('GamepadService never listened for events');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await pumpEventQueue();
  });

  tearDown(() {
    // Stop this test's service, or it handles the next test's events.
    service.dispose();
    container.dispose();
  });

  test('A on a pad with no name is confirm (8BitDo Pro 2 in X mode)', () async {
    fake.pads = [('pad1', '')];
    final actions = <GameAction>[];
    final sub = inputActionBus.stream.listen(actions.add);
    fake.events.add(_button('a', 1));
    fake.events.add(_button('a', 0));
    await pumpEventQueue();
    await sub.cancel();
    expect(actions, contains(GameAction.confirm));
  });

  test('a pad the start-up scan missed is listed once it sends input', () async {
    expect(service.getDetectedControllers(), isEmpty);
    fake.pads = [('pad1', '8BitDo Pro 2')];
    fake.events.add(_button('a', 1));
    fake.events.add(_button('a', 0));
    await pumpEventQueue();
    expect(service.getDetectedControllers().map((c) => c['name']), ['8BitDo Pro 2']);
  });

  test('Refresh finds a pad that appeared after start-up without any input (#195)', () async {
    expect(service.getDetectedControllers(), isEmpty);
    fake.pads = [('pad1', 'GPD WIN 5 Controller')];
    await service.refreshControllers();
    expect(service.getDetectedControllers().map((c) => c['name']), ['GPD WIN 5 Controller']);
  });

  test('overlapping refreshes share one scan', () async {
    fake.pads = [('pad1', 'Pad')];
    final a = service.refreshControllers();
    final b = service.refreshControllers();
    expect(identical(a, b), isTrue);
    await Future.wait([a, b]);
    expect(service.getDetectedControllers(), hasLength(1));
  });
}
