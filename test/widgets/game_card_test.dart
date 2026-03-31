import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/ui/widgets/game_card.dart';

void main() {
  group('GameCard Widget', () {
    final game = Game(
      id: '1',
      name: 'Test Game (USA)',
      platformDisplayName: 'GBA',
      fileSize: 1024,
    );

    testWidgets('renders game title correctly', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GameCard(
            game: game,
            onDownload: () {},
            onLaunch: () {},
            onDelete: () {},
          ),
        ),
      ));

      expect(find.text('Test Game'), findsOneWidget);
    });

    testWidgets('shows download button when not downloaded', (WidgetTester tester) async {
      bool downloadTapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GameCard(
            game: game,
            isDownloaded: false,
            onDownload: () => downloadTapped = true,
            onLaunch: () {},
            onDelete: () {},
          ),
        ),
      ));

      final downloadBtn = find.byIcon(Icons.download);
      expect(downloadBtn, findsOneWidget);
      
      await tester.tap(downloadBtn);
      expect(downloadTapped, isTrue);
    });

    testWidgets('shows play button when downloaded', (WidgetTester tester) async {
      bool launchTapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GameCard(
            game: game,
            isDownloaded: true,
            onDownload: () {},
            onLaunch: () => launchTapped = true,
            onDelete: () {},
          ),
        ),
      ));

      final playBtn = find.byIcon(Icons.play_arrow);
      expect(playBtn, findsOneWidget);
      
      await tester.tap(playBtn);
      expect(launchTapped, isTrue);
    });

    testWidgets('shows checkmark when downloaded', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GameCard(
            game: game,
            isDownloaded: true,
            onDownload: () {},
            onLaunch: () {},
            onDelete: () {},
          ),
        ),
      ));

      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });
}
