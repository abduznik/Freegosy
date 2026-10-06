import 'package:flutter/material.dart';

/// Tells the user that settings couldn't be saved or read (portable drive
/// removed, damaged file kept aside): always logged, shown at most every
/// 30 s. A problem found before the app is on screen (the settings file is
/// first read before `runApp`) is held back until [showPending].
class StorageProblemReporter {
  StorageProblemReporter(this.messengerKey, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final DateTime Function() _now;
  static const quietPeriod = Duration(seconds: 30);

  DateTime? _lastShown;
  String? _pending;

  void report(String message) {
    debugPrint('[Portable] $message');
    final messenger = messengerKey.currentState;
    if (messenger == null) {
      // Not on screen yet: keep it (the newest) and don't start the quiet period.
      _pending = message;
      return;
    }
    _pending = null;
    _show(messenger, message);
  }

  /// Shows the message held back while there was no app to show it in.
  void showPending() {
    final message = _pending;
    final messenger = messengerKey.currentState;
    if (message == null || messenger == null) return;
    _pending = null;
    _show(messenger, message);
  }

  void _show(ScaffoldMessengerState messenger, String message) {
    final now = _now();
    if (_lastShown != null && now.difference(_lastShown!) < quietPeriod) return;
    _lastShown = now;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
