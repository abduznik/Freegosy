import 'package:flutter/material.dart';
import '../../../core/romm/romm_models.dart';

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
            IconButton(
              icon: const Icon(Icons.add_comment, color: Colors.blue),
              onPressed: onAddNote,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (notes.isEmpty)
          const Text('No notes added yet.', style: TextStyle(color: Colors.white54, fontSize: 13))
        else
          ...notes.map((note) => Card(
                color: Colors.white10,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => onViewNote(note),
                  title: Text(
                    note.title.isNotEmpty ? note.title : 'Note',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    note.content,
                    style: const TextStyle(color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
                    onPressed: () => onDeleteNote(note.id),
                  ),
                ),
              )),
      ],
    );
  }
}
