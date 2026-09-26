import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/retroachievements/retroachievements_game_models.dart';
import '../../../core/retroachievements/retroachievements_models.dart';
import '../../../core/romm/romm_models.dart';
import '../../../providers/retroachievements_provider.dart';
import '../dialog_back_bridge.dart';
import '../focus_effect_wrapper.dart';

const _hardcoreGold = Color(0xFFFFC107);

/// Game detail section listing a game's RetroAchievements set.
///
/// Shown only when RomM matched the ROM to an RA game (`ra_id`). Unlock
/// state comes from, in order of preference:
///  1. the RA Web API, live, when a Web API key is saved in Settings;
///  2. the progress RomM synced for the user (`ra_progression`), when the
///     server has RA enabled and the user linked their RA username in RomM;
///  3. otherwise none — RomM's stored achievement set is shown without it.
class GameAchievementsSection extends ConsumerWidget {
  final Game game;

  const GameAchievementsSection({super.key, required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raId = game.raId;
    if (raId == null) return const SizedBox.shrink();

    final credentials = ref.watch(retroAchievementsCredentialsProvider).asData?.value;
    if (credentials == null || !credentials.hasWebApiKey) {
      return _buildFromRomm(ref, raId, hasAccount: credentials != null);
    }

    return ref.watch(retroAchievementsGameProgressProvider(raId)).when(
          data: (progress) => progress == null
              ? _AchievementsBody(achievements: game.raAchievements)
              : _AchievementsBody(achievements: progress.achievements, progress: progress),
          loading: () => _AchievementsBody(achievements: game.raAchievements, isLoading: true),
          error: (e, _) => _AchievementsBody(
            achievements: game.raAchievements,
            footer: e is RetroAchievementsAuthException
                ? 'RetroAchievements rejected your Web API key — update it in Settings.'
                : 'Could not load your RetroAchievements progress.',
          ),
        );
  }

  Widget _buildFromRomm(WidgetRef ref, int raId, {required bool hasAccount}) {
    final progression = ref.watch(rommRetroAchievementsProgressionProvider).asData?.value[raId];
    if (progression != null && game.raAchievements.isNotEmpty) {
      final progress = RetroAchievementsGameProgress.fromRomm(
        gameId: raId,
        achievements: game.raAchievements,
        progression: progression,
      );
      return _AchievementsBody(
        achievements: progress.achievements,
        progress: progress,
        footer: 'Progress as last synced by RomM.',
      );
    }
    return _AchievementsBody(
      achievements: game.raAchievements,
      footer: hasAccount
          ? 'Add your Web API key in Settings → RetroAchievements to see your unlocks.'
          : 'Connect your RetroAchievements account in Settings to see your unlocks.',
    );
  }
}

class _AchievementsBody extends StatelessWidget {
  final List<RetroAchievement> achievements;

  /// Non-null when unlock state is known; null means "set only".
  final RetroAchievementsGameProgress? progress;
  final bool isLoading;
  final String? footer;

  const _AchievementsBody({required this.achievements, this.progress, this.isLoading = false, this.footer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = this.progress;
    final award = progress?.highestAward;
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Achievements',
              style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            if (award != null) _AwardChip(award: award),
            if (isLoading) ...[
              const SizedBox(width: 12),
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (progress != null && progress.totalCount > 0) ...[
          Text(
            '${progress.unlockedCount} / ${progress.totalCount} unlocked'
            ' · ${progress.earnedPoints} / ${progress.totalPoints} points'
            '${progress.unlockedHardcoreCount > 0 ? ' · ${progress.unlockedHardcoreCount} hardcore' : ''}',
            style: muted,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.unlockedCount / progress.totalCount,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 12),
        ] else if (achievements.isNotEmpty) ...[
          Text('${achievements.length} achievements · ${achievements.fold<int>(0, (s, a) => s + a.points)} points', style: muted),
          const SizedBox(height: 12),
        ] else if (!isLoading) ...[
          Text(
            progress != null ? 'This game has no achievements yet.' : 'This game is on RetroAchievements.',
            style: muted,
          ),
          const SizedBox(height: 8),
        ],
        if (achievements.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in achievements)
                _BadgeTile(achievement: a, showLockState: progress != null),
            ],
          ),
        if (footer != null) ...[
          const SizedBox(height: 8),
          Text(footer!, style: muted.copyWith(fontSize: 12)),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _AwardChip extends StatelessWidget {
  final RetroAchievementsAward award;
  const _AwardChip({required this.award});

  @override
  Widget build(BuildContext context) {
    final color = switch (award) {
      RetroAchievementsAward.mastered => _hardcoreGold,
      RetroAchievementsAward.beatenHardcore => _hardcoreGold,
      _ => Theme.of(context).colorScheme.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events, size: 14, color: color),
          const SizedBox(width: 4),
          Text(award.label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final RetroAchievement achievement;

  /// When false, unlock state is unknown and the colour badge is shown.
  final bool showLockState;

  const _BadgeTile({required this.achievement, required this.showLockState});

  @override
  Widget build(BuildContext context) {
    final locked = showLockState && !achievement.isUnlocked;
    final hardcore = showLockState && achievement.isUnlockedHardcore;
    return Tooltip(
      message: achievement.title,
      child: FocusEffectWrapper(
        borderRadius: 8,
        scaleFactor: 1.1,
        onTap: () => _showDetails(context),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hardcore ? _hardcoreGold : Colors.transparent, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CachedNetworkImage(
              imageUrl: locked ? achievement.lockedBadgeUrl : achievement.badgeUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: Colors.grey[900]),
              errorWidget: (_, __, ___) => Container(
                color: Colors.grey[900],
                child: const Icon(Icons.emoji_events_outlined, color: Colors.white38),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => DialogBackBridge(
        child: AlertDialog(
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(imageUrl: achievement.badgeUrl, width: 48, height: 48),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(achievement.title)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(achievement.description),
              const SizedBox(height: 16),
              Text('${achievement.points} points${_typeLabel(achievement.type)}'),
              if (achievement.numAwarded > 0)
                Text('Unlocked by ${achievement.numAwarded} players (${achievement.numAwardedHardcore} hardcore)'),
              if (showLockState) ...[
                const SizedBox(height: 8),
                Text(
                  achievement.isUnlockedHardcore
                      ? 'Unlocked in hardcore on ${_formatDate(achievement.dateEarnedHardcore!)}'
                      : achievement.isUnlocked
                          ? 'Unlocked on ${_formatDate(achievement.dateEarned!)}'
                          : 'Locked',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: achievement.isUnlockedHardcore ? _hardcoreGold : null,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(String? type) => switch (type) {
        'progression' => ' · Progression',
        'win_condition' => ' · Win condition',
        'missable' => ' · Missable',
        _ => '',
      };

  static String _formatDate(DateTime d) {
    final local = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}
