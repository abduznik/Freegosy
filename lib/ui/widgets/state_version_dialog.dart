import 'package:flutter/material.dart';

/// Asks before loading a save state made by a different emulator build.
/// True only for "Load anyway"; Cancel, back and tapping outside are false.
Future<bool> showStateVersionDialog(
  BuildContext context, {
  required String slotLabel,
  required String emulatorName,
  required String stateVersion,
  required String installed,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.warning_amber_rounded, color: Colors.orange),
        SizedBox(width: 12),
        Text('Different emulator version'),
      ]),
      content: Text(
          '$slotLabel was made with $emulatorName $stateVersion, you have $installed. It may not load.'),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Load anyway'),
        ),
      ],
    ),
  );
  return result ?? false;
}
