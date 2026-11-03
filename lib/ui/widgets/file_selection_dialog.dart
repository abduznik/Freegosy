import 'package:flutter/material.dart';
import '../../core/romm/romm_models.dart';

/// Lets the user pick which of a multi-file game's files to download.
/// Pops the chosen indexes into [Game.files], or null when cancelled.
class FileSelectionDialog extends StatefulWidget {
  final Game game;

  const FileSelectionDialog({super.key, required this.game});

  static Future<List<int>?> show(BuildContext context, Game game) =>
      showDialog<List<int>>(context: context, builder: (_) => FileSelectionDialog(game: game));

  @override
  State<FileSelectionDialog> createState() => _FileSelectionDialogState();
}

class _FileSelectionDialogState extends State<FileSelectionDialog> {
  final _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = widget.game.files;
    final count = _selected.length;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Select Files'),
      content: SizedBox(
        width: double.maxFinite,
        // A game can list hundreds of files: the list scrolls, the dialog does not grow.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select which files to download:',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (context, i) {
                  final file = files[i];
                  final sizeMB = (((file['file_size_bytes'] as num?) ?? 0) / (1024 * 1024)).toStringAsFixed(1);
                  return CheckboxListTile(
                    dense: true,
                    value: _selected.contains(i),
                    onChanged: (val) => setState(() {
                      if (val == true) {
                        _selected.add(i);
                      } else {
                        _selected.remove(i);
                      }
                    }),
                    title: Text(
                      file['file_name']?.toString() ?? 'Unknown',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '$sizeMB MB',
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: count == 0 ? null : () => Navigator.pop(context, (_selected.toList()..sort())),
          child: Text('Download $count File${count == 1 ? '' : 's'}'),
        ),
      ],
    );
  }
}
