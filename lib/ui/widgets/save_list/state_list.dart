import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/save/resume_service.dart';
import '../game_detail/resume_slots_dialog.dart';

/// A game's save states (this PC and RomM), as the Resume list shows them.
class StateList extends StatelessWidget {
  const StateList({super.key, required this.states, required this.onSelect, this.selected, this.thumbnailFor});

  final List<ResumeEntry> states;
  final ValueChanged<ResumeEntry> onSelect;
  final ResumeEntry? selected;
  final Future<Uint8List?> Function(ResumeEntry entry)? thumbnailFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (states.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No save states', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final s in states)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: identical(s, selected) ? theme.colorScheme.primary : Colors.transparent),
          ),
          child: ResumeSlotRow(
            key: ValueKey('state-row-${s.fileName}'),
            entry: s,
            autofocus: false,
            showEmulator: true,
            thumbnailFor: thumbnailFor,
            onTap: () => onSelect(s),
          ),
        ),
    ]);
  }
}
