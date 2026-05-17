import 'package:flutter/material.dart';
import '../focus_effect_wrapper.dart';

class GamePersonalSection extends StatelessWidget {
  final String? status;
  final int rating;
  final int completion;
  final bool backlogged;
  final bool nowPlaying;
  final bool isSaving;
  final bool adjustingRating;
  final bool adjustingCompletion;
  final Function(String?) onStatusChanged;
  final Function(int) onRatingChanged;
  final Function(int) onCompletionChanged;
  final Function(bool) onBacklogChanged;
  final Function(bool) onNowPlayingChanged;
  final VoidCallback onToggleAdjustingRating;
  final VoidCallback onToggleAdjustingCompletion;
  final VoidCallback onSave;

  const GamePersonalSection({
    super.key,
    required this.status,
    required this.rating,
    required this.completion,
    required this.backlogged,
    required this.nowPlaying,
    required this.isSaving,
    required this.adjustingRating,
    required this.adjustingCompletion,
    required this.onStatusChanged,
    required this.onRatingChanged,
    required this.onCompletionChanged,
    required this.onBacklogChanged,
    required this.onNowPlayingChanged,
    required this.onToggleAdjustingRating,
    required this.onToggleAdjustingCompletion,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
        const SizedBox(height: 8),
        Text(
          'Personal',
          style: theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        Center(
          child: SizedBox(
            width: 384,
            child: Column(
              children: [
                // 1. Status Button Alone (Full width 320, with label on left and status value on the right)
                FocusEffectWrapper(
                  onTap: () async {
                    final selected = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Select Status'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            'never_playing',
                            'incomplete',
                            'finished',
                            'completed_100',
                            'retired'
                          ].map((val) {
                            String label = 'Not set';
                            IconData icon = Icons.help_outline;
                            if (val == 'never_playing') { label = 'Never Played'; icon = Icons.star_border; }
                            else if (val == 'incomplete') { label = 'Incomplete'; icon = Icons.hourglass_empty; }
                            else if (val == 'finished') { label = 'Finished'; icon = Icons.check_circle_outline; }
                            else if (val == 'completed_100') { label = '100% Completed'; icon = Icons.emoji_events; }
                            else if (val == 'retired') { label = 'Dropped'; icon = Icons.cancel_outlined; }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: FocusEffectWrapper(
                                onTap: () => Navigator.pop(ctx, val),
                                borderRadius: 16.0,
                                scaleFactor: 1.0,
                                autofocus: val == (status ?? 'never_playing'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: status == val ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                                    border: Border.all(color: status == val ? theme.colorScheme.primary.withValues(alpha: 0.4) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(icon, color: status == val ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                                      const SizedBox(width: 16),
                                      Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        actions: [
                          FocusEffectWrapper(
                            onTap: () => Navigator.pop(ctx),
                            borderRadius: 16.0,
                            scaleFactor: 1.0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                              ),
                              child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (selected != null) onStatusChanged(selected);
                  },
                  borderRadius: 16.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                      border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(
                          'Status',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const Spacer(),
                        Text(
                          status == 'never_playing' ? 'Never Played' :
                          status == 'incomplete' ? 'Incomplete' :
                          status == 'finished' ? 'Finished' :
                          status == 'completed_100' ? '100% Completed' :
                          status == 'retired' ? 'Dropped' : 'Not set',
                          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6), size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Rating & Progress Side-by-Side
                Row(
                  children: [
                    Expanded(
                      child: FocusEffectWrapper(
                        onTap: adjustingRating ? null : onToggleAdjustingRating,
                        borderRadius: 16.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: adjustingRating 
                                ? theme.colorScheme.primaryContainer 
                                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                            border: Border.all(
                              color: adjustingRating 
                                  ? theme.colorScheme.primary 
                                  : theme.colorScheme.outline.withValues(alpha: 0.3),
                              width: adjustingRating ? 2.0 : 1.0,
                            ),
                          ),
                          child: adjustingRating
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => onRatingChanged((rating - 1).clamp(0, 10)),
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
                                          ),
                                          child: Icon(Icons.remove, size: 12, color: theme.colorScheme.onPrimaryContainer),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: onToggleAdjustingRating,
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Text(
                                            rating > 0 ? '$rating Star' : 'No Rating',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 12, 
                                              fontWeight: FontWeight.bold, 
                                              color: theme.colorScheme.onPrimaryContainer
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => onRatingChanged((rating + 1).clamp(0, 10)),
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
                                          ),
                                          child: Icon(Icons.add, size: 12, color: theme.colorScheme.onPrimaryContainer),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.star, size: 14, color: Colors.amber),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        rating > 0 ? '$rating Star' : 'Rating',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12, 
                                          fontWeight: FontWeight.bold, 
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.9)
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FocusEffectWrapper(
                        onTap: adjustingCompletion ? null : onToggleAdjustingCompletion,
                        borderRadius: 16.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: adjustingCompletion 
                                ? theme.colorScheme.primaryContainer 
                                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                            border: Border.all(
                              color: adjustingCompletion 
                                  ? theme.colorScheme.primary 
                                  : theme.colorScheme.outline.withValues(alpha: 0.3),
                              width: adjustingCompletion ? 2.0 : 1.0,
                            ),
                          ),
                          child: adjustingCompletion
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => onCompletionChanged((completion - 5).clamp(0, 100)),
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
                                          ),
                                          child: Icon(Icons.remove, size: 12, color: theme.colorScheme.onPrimaryContainer),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: onToggleAdjustingCompletion,
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Text(
                                            '$completion%',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 12, 
                                              fontWeight: FontWeight.bold, 
                                              color: theme.colorScheme.onPrimaryContainer
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => onCompletionChanged((completion + 5).clamp(0, 100)),
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
                                          ),
                                          child: Icon(Icons.add, size: 12, color: theme.colorScheme.onPrimaryContainer),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.hourglass_empty, size: 14, color: theme.colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        '$completion% Done',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12, 
                                          fontWeight: FontWeight.bold, 
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.9)
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 3. Backlog & Playing Side-by-Side
                Row(
                  children: [
                    Expanded(
                      child: FocusEffectWrapper(
                        onTap: () => onBacklogChanged(!backlogged),
                        borderRadius: 16.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: backlogged 
                                ? theme.colorScheme.primary 
                                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                            border: Border.all(
                              color: backlogged 
                                  ? theme.colorScheme.primary 
                                  : theme.colorScheme.outline.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(backlogged ? Icons.bookmark : Icons.bookmark_border, size: 14, color: backlogged ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Backlog',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12, 
                                    fontWeight: FontWeight.bold, 
                                    color: backlogged ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface.withValues(alpha: 0.9)
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FocusEffectWrapper(
                        onTap: () => onNowPlayingChanged(!nowPlaying),
                        borderRadius: 16.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: nowPlaying 
                                ? theme.colorScheme.primary 
                                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                            border: Border.all(
                              color: nowPlaying 
                                  ? theme.colorScheme.primary 
                                  : theme.colorScheme.outline.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(nowPlaying ? Icons.play_circle_fill : Icons.play_circle_outline, size: 14, color: nowPlaying ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Playing',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12, 
                                    fontWeight: FontWeight.bold, 
                                    color: nowPlaying ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface.withValues(alpha: 0.9)
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 4. Save Changes Button Alone at the very bottom
        Center(
          child: SizedBox(
            width: 288,
            child: FocusEffectWrapper(
              onTap: isSaving ? null : onSave,
              borderRadius: 16.0,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: isSaving
                      ? null
                      : LinearGradient(
                          colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: isSaving ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25) : null,
                  border: Border.all(
                    color: isSaving
                        ? theme.colorScheme.outline.withValues(alpha: 0.3)
                        : theme.colorScheme.primary.withValues(alpha: 0.3),
                    width: 1.0,
                  ),
                ),
                child: isSaving
                    ? SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary),
                      )
                    : Text(
                        'Save Changes',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
