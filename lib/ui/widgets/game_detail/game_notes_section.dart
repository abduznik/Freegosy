import 'package:flutter/material.dart';
import '../../../core/romm/romm_models.dart';
import '../focus_effect_wrapper.dart';

class GameNotesSection extends StatelessWidget {
  final List<RomNote> notes;
  final VoidCallback onAddNote;
  final Function(RomNote) onViewNote;

  const GameNotesSection({
    super.key,
    required this.notes,
    required this.onAddNote,
    required this.onViewNote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Notes',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            FocusEffectWrapper(
              onTap: onAddNote,
              borderRadius: 12.0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.blue.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add_comment, size: 16, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Text('Add Note', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (notes.isEmpty)
          const Text('No notes added yet.', style: TextStyle(color: Colors.white54, fontSize: 13))
        else
          ...notes.map((note) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: FocusEffectWrapper(
                  onTap: () => onViewNote(note),
                  borderRadius: 12.0,
                  scaleFactor: 1.015,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.03),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.title.isNotEmpty ? note.title : 'Note',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          note.content,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              )),
      ],
    );
  }
}
