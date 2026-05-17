import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../focus_effect_wrapper.dart';

class GamePersonalSection extends StatefulWidget {
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
  State<GamePersonalSection> createState() => _GamePersonalSectionState();
}

class _GamePersonalSectionState extends State<GamePersonalSection> {
  bool _adjustingRating = false;
  bool _adjustingCompletion = false;

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
                              autofocus: val == (widget.status ?? 'never_playing'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: widget.status == val ? Colors.indigo.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
                                  border: Border.all(color: widget.status == val ? Colors.indigo.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(icon, color: widget.status == val ? Colors.indigoAccent : Colors.white54),
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
                  if (selected != null) widget.onStatusChanged(selected);
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
                        widget.status == 'never_playing' ? 'Never' :
                        widget.status == 'incomplete' ? 'Incomplete' :
                        widget.status == 'finished' ? 'Finished' :
                        widget.status == 'completed_100' ? '100%' :
                        widget.status == 'retired' ? 'Dropped' : 'Not set',
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
                onTap: () {
                  setState(() {
                    _adjustingRating = !_adjustingRating;
                  });
                },
                onKeyEvent: (node, event) {
                  if (event is! KeyUpEvent) {
                    if (_adjustingRating) {
                      if (event.logicalKey == LogicalKeyboardKey.enter || 
                          event.logicalKey == LogicalKeyboardKey.space ||
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        setState(() {
                          _adjustingRating = false;
                        });
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        if (widget.rating > 0) {
                          widget.onRatingChanged(widget.rating - 1);
                        }
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        if (widget.rating < 10) {
                          widget.onRatingChanged(widget.rating + 1);
                        }
                        return KeyEventResult.handled;
                      }
                      // Block D-pad Up/Down while adjusting rating!
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp || 
                          event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        return KeyEventResult.handled;
                      }
                    } else {
                      // Press enter/space to enter adjust mode
                      if (event.logicalKey == LogicalKeyboardKey.enter || 
                          event.logicalKey == LogicalKeyboardKey.space) {
                        setState(() {
                          _adjustingRating = true;
                        });
                        return KeyEventResult.handled;
                      }
                    }
                  }
                  return KeyEventResult.ignored;
                },
                borderRadius: 12.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _adjustingRating 
                        ? Colors.indigo.withValues(alpha: 0.1) 
                        : Colors.white.withValues(alpha: 0.03),
                    border: Border.all(
                      color: _adjustingRating 
                          ? Colors.indigoAccent 
                          : Colors.white.withValues(alpha: 0.05),
                      width: _adjustingRating ? 2.0 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Rating', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                          if (_adjustingRating)
                            const Padding(
                              padding: EdgeInsets.only(top: 2.0),
                              child: Text('[←/→] Adjust', style: TextStyle(color: Colors.indigoAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: List.generate(10, (i) => GestureDetector(
                          onTap: _adjustingRating ? () => widget.onRatingChanged(i + 1) : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1.0),
                            child: Icon(
                              i < widget.rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 13,
                            ),
                          ),
                        )),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Row 2: Completion Slider horizontally aligned with Console Slider Locking Mode
        FocusEffectWrapper(
          onTap: () {
            setState(() {
              _adjustingCompletion = !_adjustingCompletion;
            });
          },
          onKeyEvent: (node, event) {
            if (event is! KeyUpEvent) {
              if (_adjustingCompletion) {
                if (event.logicalKey == LogicalKeyboardKey.enter || 
                    event.logicalKey == LogicalKeyboardKey.space ||
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  setState(() {
                    _adjustingCompletion = false;
                  });
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  if (widget.completion > 0) {
                    widget.onCompletionChanged((widget.completion - 5).clamp(0, 100));
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  if (widget.completion < 100) {
                    widget.onCompletionChanged((widget.completion + 5).clamp(0, 100));
                  }
                  return KeyEventResult.handled;
                }
                // Block D-pad Up/Down while adjusting to avoid navigation slip!
                if (event.logicalKey == LogicalKeyboardKey.arrowUp || 
                    event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  return KeyEventResult.handled;
                }
              } else {
                // Enter adjust mode on Enter/Space
                if (event.logicalKey == LogicalKeyboardKey.enter || 
                    event.logicalKey == LogicalKeyboardKey.space) {
                  setState(() {
                    _adjustingCompletion = true;
                  });
                  return KeyEventResult.handled;
                }
              }
            }
            return KeyEventResult.ignored;
          },
          borderRadius: 12.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _adjustingCompletion 
                  ? Colors.indigo.withValues(alpha: 0.1) 
                  : Colors.white.withValues(alpha: 0.03),
              border: Border.all(
                color: _adjustingCompletion 
                    ? Colors.indigoAccent 
                    : Colors.white.withValues(alpha: 0.05),
                width: _adjustingCompletion ? 2.0 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Completion', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                    if (_adjustingCompletion)
                      const Padding(
                        padding: EdgeInsets.only(top: 2.0),
                        child: Text('[←/→] Adjust  [Enter] Save', style: TextStyle(color: Colors.indigoAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: _adjustingCompletion ? 8 : 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: widget.completion.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      activeColor: Colors.indigoAccent,
                      onChanged: _adjustingCompletion 
                          ? (val) => widget.onCompletionChanged(val.toInt())
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${widget.completion}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Row 3: Toggles side-by-side
        Row(
          children: [
            Expanded(
              child: FocusEffectWrapper(
                onTap: () => widget.onBacklogChanged(!widget.backlogged),
                borderRadius: 12.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: widget.backlogged ? Colors.indigo.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.03),
                    border: Border.all(color: widget.backlogged ? Colors.indigo.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      Icon(widget.backlogged ? Icons.bookmark : Icons.bookmark_border, color: widget.backlogged ? Colors.indigoAccent : Colors.white54, size: 18),
                      const SizedBox(width: 8),
                      const Text('Backlog', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const Spacer(),
                      SizedBox(
                        width: 28,
                        height: 18,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Switch(
                            value: widget.backlogged,
                            onChanged: widget.onBacklogChanged,
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
                onTap: () => widget.onNowPlayingChanged(!widget.nowPlaying),
                borderRadius: 12.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: widget.nowPlaying ? Colors.indigo.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.03),
                    border: Border.all(color: widget.nowPlaying ? Colors.indigo.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      Icon(widget.nowPlaying ? Icons.play_circle_fill : Icons.play_circle_outline, color: widget.nowPlaying ? Colors.indigoAccent : Colors.white54, size: 18),
                      const SizedBox(width: 8),
                      const Text('Playing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const Spacer(),
                      SizedBox(
                        width: 28,
                        height: 18,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Switch(
                            value: widget.nowPlaying,
                            onChanged: widget.onNowPlayingChanged,
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
              onTap: widget.isSaving ? null : widget.onSave,
              borderRadius: 12.0,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: widget.isSaving
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: widget.isSaving ? Colors.white.withValues(alpha: 0.05) : null,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                ),
                child: widget.isSaving
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
