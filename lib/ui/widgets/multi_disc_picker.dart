import 'package:flutter/material.dart';
import '../../core/romm/romm_models.dart';

class MultiDiscPicker extends StatelessWidget {
  final Game game;
  final List<Map<String, dynamic>> files; // list of file objects from game.files
  final Function(Map<String, dynamic>) onSelect;

  const MultiDiscPicker({
    super.key,
    required this.game,
    required this.files,
    required this.onSelect,
  });

  static Future<void> show(
    BuildContext context, {
    required Game game,
    required List<Map<String, dynamic>> files,
    required Function(Map<String, dynamic>) onSelect,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => MultiDiscPicker(
        game: game,
        files: files,
        onSelect: onSelect,
      ),
    );
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _discLabel(String filename, int index) {
    // Try to detect disc number from filename
    final lower = filename.toLowerCase();
    final discMatch = RegExp(r'disc\s*(\d+)|disk\s*(\d+)|cd\s*(\d+)|part\s*(\d+)').firstMatch(lower);
    if (discMatch != null) {
      final num = discMatch.group(1) ?? discMatch.group(2) ?? discMatch.group(3) ?? discMatch.group(4);
      return 'Disc $num';
    }
    return 'File ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.album_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Disc',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        game.displayName,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12),
          // File list - Expanded and Scrollable
          Expanded(
            child: ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                final filename = file['file_name']?.toString() ?? file['name']?.toString() ?? 'File ${index + 1}';
                final size = file['file_size_bytes'] as int?;
                final label = _discLabel(filename, index);

                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(label),
                    subtitle: Text(
                      filename,
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: size != null
                        ? Text(
                            _formatSize(size),
                            style: const TextStyle(fontSize: 11, color: Colors.white38),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      onSelect(file);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
