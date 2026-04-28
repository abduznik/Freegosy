import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/save/save_sync_service.dart';

class SaveConflictDialog extends StatelessWidget {
  final SaveConflictException conflict;

  const SaveConflictDialog({super.key, required this.conflict});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 12),
          Text('Sync Conflict Detected'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Both local and cloud saves have been modified for ${conflict.game.name}. Please choose which version to keep.',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 24),
          _buildOption(
            context,
            title: 'Use Local Version',
            time: conflict.localTime,
            dateFormat: dateFormat,
            icon: Icons.computer,
            onTap: () => Navigator.pop(context, 'local'),
            isNewer: conflict.localTime.isAfter(conflict.cloudTime),
          ),
          const SizedBox(height: 12),
          _buildOption(
            context,
            title: 'Use Cloud Version',
            time: conflict.cloudTime,
            dateFormat: dateFormat,
            icon: Icons.cloud_outlined,
            onTap: () => Navigator.pop(context, 'cloud'),
            isNewer: conflict.cloudTime.isAfter(conflict.localTime),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel Sync'),
        ),
      ],
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required String title,
    required DateTime time,
    required DateFormat dateFormat,
    required IconData icon,
    required VoidCallback onTap,
    required bool isNewer,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isNewer ? Colors.deepPurple : Colors.grey.withValues(alpha: 0.3),
            width: isNewer ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isNewer ? Colors.deepPurple.withValues(alpha: 0.05) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: isNewer ? Colors.deepPurple : Colors.grey),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (isNewer) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NEWER',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    'Modified: ${dateFormat.format(time)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
