import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/strategy_lock.dart';

void main() {
  test('runs bodies one after another, in call order', () async {
    final lock = StrategyLock();
    final log = <String>[];
    Future<void> body(String name) async {
      log.add('$name start');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      log.add('$name end');
    }

    await Future.wait([lock.run(() => body('a')), lock.run(() => body('b'))]);
    expect(log, ['a start', 'a end', 'b start', 'b end']);
  });

  test('a body may run another one inside it', () async {
    final lock = StrategyLock();
    expect(await lock.run(() => lock.run(() async => 7)), 7);
  });

  test('a failing body frees the lock and passes its error on', () async {
    final lock = StrategyLock();
    await expectLater(lock.run<void>(() async => throw StateError('x')), throwsStateError);
    expect(await lock.run(() async => 1), 1);
  });

  test('waiting longer than a minute behind a stuck operation is logged, once', () {
    fakeAsync((async) {
      final slow = <String>[];
      final lock = StrategyLock(onSlow: slow.add, createTimer: Timer.new);
      lock.run(() => Completer<void>().future); // never finishes
      lock.run(() async {});
      async.elapse(const Duration(seconds: 59));
      expect(slow, isEmpty);
      async.elapse(const Duration(seconds: 2));
      expect(slow, hasLength(1));
      async.elapse(const Duration(minutes: 5));
      expect(slow, hasLength(1));
    });
  });

  test('no warning when the wait ends in time', () {
    fakeAsync((async) {
      final slow = <String>[];
      final lock = StrategyLock(onSlow: slow.add, createTimer: Timer.new);
      final first = Completer<void>();
      lock.run(() => first.future);
      lock.run(() async {});
      async.elapse(const Duration(seconds: 30));
      first.complete();
      async.elapse(const Duration(minutes: 2));
      expect(slow, isEmpty);
    });
  });

  test('by default the warning timer is not a test timer: a widget test ending with a queued operation has none pending', () {
    fakeAsync((async) {
      final lock = StrategyLock();
      final first = Completer<void>();
      lock.run(() => first.future);
      lock.run(() async {});
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
      first.complete();
      async.flushMicrotasks();
    });
  });
}
