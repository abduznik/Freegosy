import 'package:flutter/material.dart';
import '../../core/save/save_sync_service.dart';
import '../widgets/save_conflict_dialog.dart';

class LibraryDialogService {
  static Future<Map<String, dynamic>?> showSaveSelectionDialog(BuildContext context, List<Map<String, dynamic>> saves) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Cloud Save'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: saves.length,
            itemBuilder: (context, index) {
              final save = saves[index];
              final fileName = save['file_name_no_ext'] ?? save['file_name'] ?? 'Unknown Save';
              final createdAtStr = save['created_at'] ?? save['updated_at'] ?? '';
              final createdAt = DateTime.tryParse(createdAtStr.toString());

              String subtitle = 'Unknown date';
              if (createdAt != null) {
                final diff = DateTime.now().difference(createdAt);
                if (diff.inDays > 0) subtitle = '${diff.inDays}d ago';
                else if (diff.inHours > 0) subtitle = '${diff.inHours}h ago';
                else if (diff.inMinutes > 0) subtitle = '${diff.inMinutes}m ago';
                else subtitle = 'just now';
              }

              return ListTile(
                title: Text(fileName.toString()),
                subtitle: Text(subtitle),
                onTap: () => Navigator.pop(context, save),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  static Future<String?> showProfileConflictDialog(BuildContext context, List<Map<String, dynamic>> profiles) async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Multiple Profiles Detected'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Multiple save profiles have recent activity. Which one would you like to use?'),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final id = profile['id'] as String;
                    final lastActive = profile['newestFile'] as DateTime;
                    
                    final diff = DateTime.now().difference(lastActive);
                    String timeAgo;
                    if (diff.inDays > 0) timeAgo = '${diff.inDays}d ago';
                    else if (diff.inHours > 0) timeAgo = '${diff.inHours}h ago';
                    else if (diff.inMinutes > 0) timeAgo = '${diff.inMinutes}m ago';
                    else timeAgo = 'just now';

                    return ListTile(
                      title: Text(id),
                      subtitle: Text('Last active: $timeAgo'),
                      onTap: () => Navigator.pop(context, id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  static Future<String?> showFolderMappingDialog(BuildContext context, dynamic strategy) async {
    final folders = await strategy.getAvailableSaveFolders();
    if (!context.mounted) return null;

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Save Folder'),
        content: SizedBox(
          width: double.maxFinite,
          child: folders.isEmpty
              ? const Text('No saves found. Launch the game in the emulator first.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final folder = folders[index];
                    final name = folder['name'] as String;
                    final date = folder['lastModified'] as DateTime;
                    
                    final diff = DateTime.now().difference(date);
                    String timeAgo;
                    if (diff.inDays > 0) timeAgo = '${diff.inDays}d ago';
                    else if (diff.inHours > 0) timeAgo = '${diff.inHours}h ago';
                    else if (diff.inMinutes > 0) timeAgo = '${diff.inMinutes}m ago';
                    else timeAgo = 'just now';

                    return ListTile(
                      title: Text(name),
                      subtitle: Text('Last active: $timeAgo'),
                      onTap: () => Navigator.pop(context, (folder['path'] ?? folder['name']) as String),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  static Future<String?> showSaveConflictDialog(BuildContext context, SaveConflictException e) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SaveConflictDialog(conflict: e),
    );
  }
}
