import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';

import '../../core/portable/portable_mode.dart';

/// Shown instead of the app when `portable.txt` is present but its folder
/// can't be written. Completes with true for "start without portable mode
/// this time"; quitting exits the process.
Future<bool> showPortableError(PortableModeException error) {
  final choice = Completer<bool>();
  runApp(_ErrorApp(
    icon: Icons.usb_off,
    message: error.toString(),
    extraAction: FilledButton(
      onPressed: () => choice.complete(true),
      child: const Text('Start without portable mode this time'),
    ),
  ));
  return choice.future;
}

/// Shown when Freegosy fails before its first screen, so the failure is
/// visible instead of leaving a process with no window.
void showStartupError(Object error) {
  runApp(_ErrorApp(icon: Icons.error_outline, message: 'Freegosy could not start:\n$error'));
}

class _ErrorApp extends StatelessWidget {
  const _ErrorApp({required this.icon, required this.message, this.extraAction});

  final IconData icon;
  final String message;
  final Widget? extraAction;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 48),
                const SizedBox(height: 16),
                SelectableText(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
                  OutlinedButton(onPressed: () => io.exit(0), child: const Text('Quit')),
                  ?extraAction,
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
