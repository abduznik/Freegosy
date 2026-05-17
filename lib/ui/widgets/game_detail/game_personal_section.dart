import 'package:flutter/material.dart';
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

        // Status dropdown
        Row(
          children: [
            const Text('Status', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const Spacer(),
            DropdownButton<String>(
              value: const [
                'never_playing',
                'incomplete',
                'finished',
                'completed_100',
                'retired'
              ].contains(status) ? status : null,
              dropdownColor: Colors.grey[900],
              style: const TextStyle(color: Colors.white),
              hint: const Text('Not set', style: TextStyle(color: Colors.white54)),
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'never_playing', child: Text('Never Played')),
                DropdownMenuItem(value: 'incomplete', child: Text('Incomplete')),
                DropdownMenuItem(value: 'finished', child: Text('Finished')),
                DropdownMenuItem(value: 'completed_100', child: Text('100% Completed')),
                DropdownMenuItem(value: 'retired', child: Text('Dropped')),
              ],
              onChanged: onStatusChanged,
            ),
          ],
        ),

        // Rating stars
        Row(
          children: [
            const Text('Rating', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const Spacer(),
            Row(
              children: List.generate(10, (i) => GestureDetector(
                onTap: () => onRatingChanged(i + 1),
                child: Icon(
                  i < rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 20,
                ),
              )),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Completion slider
        Row(
          children: [
            const Text('Completion', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const Spacer(),
            Text('$completion%', style: const TextStyle(color: Colors.white)),
          ],
        ),
        Slider(
          value: completion.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          label: '$completion%',
          onChanged: (val) => onCompletionChanged(val.toInt()),
        ),

        // Toggles row
        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                title: const Text('Backlog', style: TextStyle(fontSize: 13)),
                value: backlogged,
                onChanged: onBacklogChanged,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: SwitchListTile(
                title: const Text('Now Playing', style: TextStyle(fontSize: 13)),
                value: nowPlaying,
                onChanged: onNowPlayingChanged,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        FocusEffectWrapper(
          onTap: isSaving ? null : onSave,
          borderRadius: 16.0,
          child: Container(
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 14),
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
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Save Changes',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
