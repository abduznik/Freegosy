import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/ui/widgets/game_card.dart';
import 'package:freegosy/core/romm/romm_models.dart';

void main() {
  testWidgets('GameCard should render without overflow', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameCard(
              game: Game(
                id: '1',
                name: 'Test Game',
                fileSize: 0,
              ),
              onDownload: () {},
              onLaunch: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(GameCard), findsOneWidget);
  });
}
