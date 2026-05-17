import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../focus_effect_wrapper.dart';

class GamePersonalSection extends StatelessWidget {
  final String? status;
  final int rating;
  final int completion;
  final bool backlogged;
  final bool nowPlaying;
  final bool isSaving;
  final Function(String?) onStatusChanged;
  final Function(int) onRatingChanged;
  final Function(int) onCompletionChanged;
  final Function(bool) onBacklogChanged;
  final Function(bool) onNowPlayingChanged;
  final VoidCallback onSave;

  const GamePersonalSection({
    super.key,
    required this.status,
    required this.rating,
    required this.completion,
    required this.backlogged,
    required this.nowPlaying,
    required this.isSaving,
    required this.onStatusChanged,
    required this.onRatingChanged,
    required this.onCompletionChanged,
    required this.onBacklogChanged,
    required this.onNowPlayingChanged,
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

        // Row 1: Status & Rating side-by-side
        Row(
          children: [
            Expanded(
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
                              borderRadius: 12.0,
                              scaleFactor: 1.0,
                              autofocus: val == (status ?? 'never_playing'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
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
                  if (selected != null) onStatusChanged(selected);
                },
                borderRadius: 12.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withValues(alpha: 0.03),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      const Text('Status', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                      const Spacer(),
                      Text(
                        status == 'never_playing' ? 'Never' :
                        status == 'incomplete' ? 'Incomplete' :
                        status == 'finished' ? 'Finished' :
                        status == 'completed_100' ? '100%' :
                        status == 'retired' ? 'Dropped' : 'Not set',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 18),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FocusEffectWrapper(
                onTap: () {},
                borderRadius: 12.0,
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyUpEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        if (rating > 0) onRatingChanged(rating - 1);
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        if (rating < 10) onRatingChanged(rating + 1);
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.03),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      children: [
                        const Text('Rating', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                        const Spacer(),
                        Row(
                          children: List.generate(5, (i) => GestureDetector(
                            onTap: () => onRatingChanged((i + 1) * 2),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1.0),
                              child: Icon(
                                i * 2 < rating ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                                size: 16,
                              ),
                            ),
                          )),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Row 2: Completion Slider horizontally aligned
        FocusEffectWrapper(
          onTap: () {},
          borderRadius: 12.0,
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is! KeyUpEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  if (completion > 0) onCompletionChanged((completion - 5).clamp(0, 100));
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  if (completion < 100) onCompletionChanged((completion + 5).clamp(0, 100));
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.03),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  const Text('Completion', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: completion.toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 20,
                        activeColor: Colors.indigoAccent,
                        onChanged: (val) => onCompletionChanged(val.toInt()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$completion%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Row 3: Toggles side-by-side
        Row(
          children: [
            Expanded(
              child: FocusEffectWrapper(
                onTap: () => onBacklogChanged(!backlogged),
                borderRadius: 12.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: backlogged ? Colors.indigo.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.03),
                    border: Border.all(color: backlogged ? Colors.indigo.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      Icon(backlogged ? Icons.bookmark : Icons.bookmark_border, color: backlogged ? Colors.indigoAccent : Colors.white54, size: 18),
                      const SizedBox(width: 8),
                      const Text('Backlog', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const Spacer(),
                      SizedBox(
                        width: 28,
                        height: 18,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Switch(
                            value: backlogged,
                            onChanged: onBacklogChanged,
                            activeColor: Colors.indigoAccent,
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
                borderRadius: 12.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: nowPlaying ? Colors.indigo.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.03),
                    border: Border.all(color: nowPlaying ? Colors.indigo.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      Icon(nowPlaying ? Icons.play_circle_fill : Icons.play_circle_outline, color: nowPlaying ? Colors.indigoAccent : Colors.white54, size: 18),
                      const SizedBox(width: 8),
                      const Text('Playing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const Spacer(),
                      SizedBox(
                        width: 28,
                        height: 18,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Switch(
                            value: nowPlaying,
                            onChanged: onNowPlayingChanged,
                            activeColor: Colors.indigoAccent,
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
        const SizedBox(height: 16),

        // Row 4: Save Changes centered and compact
        Center(
          child: SizedBox(
            width: 240,
            child: FocusEffectWrapper(
              onTap: isSaving ? null : onSave,
              borderRadius: 12.0,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
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
