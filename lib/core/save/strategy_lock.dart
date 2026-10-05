import 'dart:async';

import 'package:flutter/foundation.dart';

/// Runs one save-strategy operation at a time. The save strategies are
/// shared by every game and hold one game's setup at a time (RetroArch's
/// core, Eden's folder), so two operations meeting at an await would read
/// each other's setup. Re-entrant: an operation holding the lock runs the
/// ones it starts itself straight away.
class StrategyLock {
  /// [onSlow] is told (once per wait) when an operation has waited longer
  /// than [warnAfter] for the one before it: a stuck operation stops every
  /// save operation, and the log should say so.
  StrategyLock(
      {this.warnAfter = const Duration(minutes: 1),
      void Function(String message)? onSlow,
      Timer Function(Duration duration, void Function() callback)? createTimer})
      : _onSlow = onSlow ?? debugPrint,
        // Outside any zone by default: a test's fake clock shouldn't see it
        // (a widget test may end with an operation still queued).
        _createTimer = createTimer ?? ((d, f) => Zone.root.createTimer(d, f));

  final Duration warnAfter;
  final void Function(String message) _onSlow;
  final Timer Function(Duration duration, void Function() callback) _createTimer;

  Future<void> _tail = Future<void>.value();
  final Object _held = Object();

  Future<T> run<T>(Future<T> Function() body) {
    if (Zone.current[_held] == true) return body();
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    final slow = _createTimer(warnAfter, () {
      _onSlow('[SaveSync] a save operation has waited over ${warnAfter.inSeconds} s for the one before it '
          '(a slow upload, or one that is stuck)');
    });
    return previous.then((_) {
      slow.cancel();
      return runZoned(body, zoneValues: {_held: true});
    }).whenComplete(() => done.complete());
  }
}
