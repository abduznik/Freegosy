import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/ui/widgets/game_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('GameCard Widget', () {
    final game = Game(
      id: '1',
      name: 'Test Game (USA)',
      platformDisplayName: 'GBA',
      fileSize: 1024,
    );

    testWidgets('renders game title correctly', (WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameCard(
              game: game,
            ),
          ),
        ),
      ));

      expect(find.text('Test Game'), findsOneWidget);
    });

    testWidgets('shows checkmark when downloaded', (WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameCard(
              game: game,
              isDownloaded: true,
            ),
          ),
        ),
      ));

      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('does not show buttons anymore', (WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameCard(
              game: game,
              isDownloaded: true,
            ),
          ),
        ),
      ));

      expect(find.byIcon(Icons.download), findsNothing);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.cloud_upload), findsNothing);
      expect(find.byIcon(Icons.cloud_download), findsNothing);
    });
  });
}
