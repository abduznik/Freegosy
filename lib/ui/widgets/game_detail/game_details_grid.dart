import 'package:flutter/material.dart';
import '../../../core/romm/romm_models.dart';

class GameDetailsGrid extends StatelessWidget {
  final Game game;

  const GameDetailsGrid({
    super.key,
    required this.game,
  });

  @override
  Widget build(BuildContext context) {
    final details = <String, String>{};
    if (game.companies.isNotEmpty) details['Developer'] = game.companies.join(', ');
    if (game.regions.isNotEmpty) details['Regions'] = game.regions.join(', ');
    if (game.languages.isNotEmpty) details['Languages'] = game.languages.join(', ');
    if (game.playerCount != null && game.playerCount!.isNotEmpty) details['Players'] = game.playerCount!;

    if (details.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 40,
        crossAxisSpacing: 16,
        mainAxisSpacing: 8,
      ),
      itemCount: details.length,
      itemBuilder: (context, index) {
        final entry = details.entries.elementAt(index);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.key,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            Text(
              entry.value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}
