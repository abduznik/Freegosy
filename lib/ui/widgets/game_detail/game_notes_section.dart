import 'package:flutter/material.dart';
import '../../../core/romm/romm_models.dart';
import '../focus_effect_wrapper.dart';

class GameNotesSection extends StatelessWidget {
  final List<RomNote> notes;
  final VoidCallback onAddNote;
  final Function(int) onDeleteNote;
  final Function(RomNote) onViewNote;

  const GameNotesSection({
    super.key,
    required this.notes,
    required this.onAddNote,
    required this.onDeleteNote,
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.blue.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add_comment, size: 14, color: Colors.blueAccent),
                    SizedBox(width: 6),
                    Text('Add Note', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
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
                child: Row(
                  children: [
                    Expanded(
                      child: FocusEffectWrapper(
                        onTap: () => onViewNote(note),
                        borderRadius: 12.0,
                        child: Container(
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
                    ),
                    const SizedBox(width: 8),
                    FocusEffectWrapper(
                      onTap: () => onDeleteNote(note.id),
                      borderRadius: 12.0,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.red.withValues(alpha: 0.08),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }
}
