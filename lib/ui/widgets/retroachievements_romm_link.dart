import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/retroachievements_provider.dart';
import 'dialog_back_bridge.dart';

/// RomM side of the RetroAchievements setup, shown in Settings: tells the
/// user when their RomM server can't match games to RA (only its admin can
/// fix that), and offers to link [username] on their RomM profile so RomM
/// syncs their progress.
class RetroAchievementsRommLink extends ConsumerWidget {
  /// The connected RA username, or null when no account is connected yet.
  final String? username;

  const RetroAchievementsRommLink({super.key, this.username});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(rommRetroAchievementsStatusProvider).asData?.value;
    if (status == null || status.serverEnabled == null) return const SizedBox.shrink();
    final muted = TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant);
    final username = this.username;

    if (status.serverEnabled == false) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your RomM server doesn\'t have RetroAchievements enabled, so games can\'t be matched to '
                'their achievements. Ask your server admin to set RETROACHIEVEMENTS_API_KEY and rescan the library. '
                'Signing emulators in still works without it.',
                style: muted,
              ),
            ),
          ],
        ),
      );
    }

    if (username == null) return const SizedBox.shrink();
    if (status.isLinkedTo(username)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 16, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(child: Text('Linked to your RomM profile.', style: muted)),
          ],
        ),
      );
    }
    if (!status.canLink(username)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text('Not linked to your RomM profile.', style: muted)),
          TextButton(
            onPressed: () => offerRommLink(context, ref, username),
            child: const Text('Link'),
          ),
        ],
      ),
    );
  }
}

/// Asks permission to link [username] on the user's RomM profile, then does
/// it. No-op (no dialog) when RomM can't be linked or is already linked.
Future<void> offerRommLink(BuildContext context, WidgetRef ref, String username) async {
  final status = await ref.read(rommRetroAchievementsStatusProvider.future);
  if (!status.canLink(username) || !context.mounted) return;

  final current = status.linkedUsername;
  final agreed = await showDialog<bool>(
    context: context,
    builder: (ctx) => DialogBackBridge(
      child: AlertDialog(
        title: const Text('Link RomM profile?'),
        content: Text(
          'Freegosy can set your RetroAchievements username on your RomM profile to "$username"'
          '${current != null ? ' (currently "$current")' : ''} and ask RomM to sync your progress, '
          'so it also shows up in RomM\'s web interface.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Link')),
        ],
      ),
    ),
  );
  if (agreed != true || !context.mounted) return;

  // Replace e.g. "Connected…" so the outcome shows now, not after it times out.
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  try {
    final synced = await ref.read(linkRommRetroAchievementsProvider)(username);
    messenger.showSnackBar(SnackBar(
      content: Text(synced
          ? 'Linked to RomM and synced your RetroAchievements progress.'
          : 'Linked to RomM. It will sync your progress on its next scheduled run.'),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not link your RomM profile: $e')));
  }
}
