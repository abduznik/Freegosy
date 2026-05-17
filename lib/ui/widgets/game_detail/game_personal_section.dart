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
        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        Text(
          'Personal',
          style: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        // 1. Status Button (Full width 320)
        Center(
          child: SizedBox(
            width: 320,
            child: FocusEffectWrapper(
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
                                color: status == val ? Colors.indigo.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
                                border: Border.all(color: status == val ? Colors.indigo.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: Row(
                                children: [
                                  Icon(icon, color: status == val ? Colors.indigoAccent : Colors.white54),
                                  const SizedBox(width: 16),
                                  Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
                            color: Colors.white.withValues(alpha: 0.05),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                        ),
                      ),
                    ],
                  ),
                );
                if (selected != null) onStatusChanged(selected);
              },
              borderRadius: 16.0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withValues(alpha: 0.05),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Colors.white70),
                    const SizedBox(width: 8),
                    const Text(
                      'Status',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                    ),
                    const Spacer(),
                    Text(
                      status == 'never_playing' ? 'Never Played' :
                      status == 'incomplete' ? 'Incomplete' :
                      status == 'finished' ? 'Finished' :
                      status == 'completed_100' ? '100% Completed' :
                      status == 'retired' ? 'Dropped' : 'Not set',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 2. Rating Button (Full width 320 with console locks)
        Center(
          child: SizedBox(
            width: 320,
            child: FocusEffectWrapper(
              onTap: onToggleAdjustingRating,
              borderRadius: 16.0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: adjustingRating 
                      ? Colors.indigo.withValues(alpha: 0.1) 
                      : Colors.white.withValues(alpha: 0.05),
                  border: Border.all(
                    color: adjustingRating 
                        ? Colors.indigoAccent 
                        : Colors.white.withValues(alpha: 0.08),
                    width: adjustingRating ? 2.0 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.star, size: 14, color: adjustingRating ? Colors.indigoAccent : Colors.amber),
                    const SizedBox(width: 8),
                    Text(
                      adjustingRating ? 'Rating [←/→]' : 'Rating',
                      style: TextStyle(
                        fontSize: 12, 
                        fontWeight: FontWeight.w600, 
                        color: adjustingRating ? Colors.indigoAccent : Colors.white.withValues(alpha: 0.9)
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: List.generate(10, (i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.0),
                        child: Icon(
                          i < rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 11,
                        ),
                      )),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 3. Completion Button (Full width 320 with console locks)
        Center(
          child: SizedBox(
            width: 320,
            child: FocusEffectWrapper(
              onTap: onToggleAdjustingCompletion,
              borderRadius: 16.0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: adjustingCompletion 
                      ? Colors.indigo.withValues(alpha: 0.1) 
                      : Colors.white.withValues(alpha: 0.05),
                  border: Border.all(
                    color: adjustingCompletion 
                        ? Colors.indigoAccent 
                        : Colors.white.withValues(alpha: 0.08),
                    width: adjustingCompletion ? 2.0 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_empty, size: 14, color: adjustingCompletion ? Colors.indigoAccent : Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      adjustingCompletion ? 'Progress [←/→]' : 'Progress',
                      style: TextStyle(
                        fontSize: 12, 
                        fontWeight: FontWeight.w600, 
                        color: adjustingCompletion ? Colors.indigoAccent : Colors.white.withValues(alpha: 0.9)
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: completion / 100.0,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(adjustingCompletion ? Colors.indigoAccent : Colors.indigo),
                          minHeight: 3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$completion%',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 4. Backlog & Playing Toggles (Side-by-side inside 320, styling matches backup/restore)
        Center(
          child: SizedBox(
            width: 320,
            child: Row(
              children: [
                Expanded(
                  child: FocusEffectWrapper(
                    onTap: () => onBacklogChanged(!backlogged),
                    borderRadius: 16.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: backlogged 
                            ? Colors.indigo.withValues(alpha: 0.1) 
                            : Colors.white.withValues(alpha: 0.05),
                        border: Border.all(
                          color: backlogged 
                              ? Colors.indigoAccent 
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(backlogged ? Icons.bookmark : Icons.bookmark_border, size: 14, color: backlogged ? Colors.indigoAccent : Colors.white70),
                          const SizedBox(width: 6),
                          const Text('Backlog', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
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
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: nowPlaying 
                            ? Colors.indigo.withValues(alpha: 0.1) 
                            : Colors.white.withValues(alpha: 0.05),
                        border: Border.all(
                          color: nowPlaying 
                              ? Colors.indigoAccent 
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(nowPlaying ? Icons.play_circle_fill : Icons.play_circle_outline, size: 14, color: nowPlaying ? Colors.indigoAccent : Colors.white70),
                          const SizedBox(width: 6),
                          const Text('Playing', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 5. Save Changes (Full width 240)
        Center(
          child: SizedBox(
            width: 240,
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
                      : const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: isSaving ? Colors.white.withValues(alpha: 0.05) : null,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                ),
                child: isSaving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          color: Colors.white,
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
