import 'package:flutter/material.dart';
import '../../core/save/save_sync_service.dart';
import '../widgets/save_conflict_dialog.dart';
import '../widgets/focus_effect_wrapper.dart';

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

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: FocusEffectWrapper(
                  onTap: () => Navigator.pop(context, save),
                  borderRadius: 12.0,
                  scaleFactor: 1.0,
                  autofocus: index == 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.03),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_download, color: Colors.indigoAccent),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(fileName.toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              const SizedBox(height: 4),
                              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          FocusEffectWrapper(
            onTap: () => Navigator.pop(context),
            borderRadius: 12.0,
            scaleFactor: 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
          ),
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

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: FocusEffectWrapper(
                        onTap: () => Navigator.pop(context, id),
                        borderRadius: 12.0,
                        scaleFactor: 1.0,
                        autofocus: index == 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white.withValues(alpha: 0.03),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.account_circle, color: Colors.indigoAccent),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(id, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                    const SizedBox(height: 4),
                                    Text('Last active: $timeAgo', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          FocusEffectWrapper(
            onTap: () => Navigator.pop(context),
            borderRadius: 12.0,
            scaleFactor: 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
          ),
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

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: FocusEffectWrapper(
                        onTap: () => Navigator.pop(context, (folder['path'] ?? folder['name']) as String),
                        borderRadius: 12.0,
                        scaleFactor: 1.0,
                        autofocus: index == 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white.withValues(alpha: 0.03),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.folder, color: Colors.indigoAccent),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                    const SizedBox(height: 4),
                                    Text('Last active: $timeAgo', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          FocusEffectWrapper(
            onTap: () => Navigator.pop(context),
            borderRadius: 12.0,
            scaleFactor: 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
          ),
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
