import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/ui/widgets/game_card.dart';
import 'package:freegosy/core/romm/romm_models.dart';

void main() {
  testWidgets('GameCard should be wrapped in ExcludeSemantics', (WidgetTester tester) async {
    final game = Game(
      id: '1',
      name: 'Test Game',
      fileSize: 100,
      fileName: 'test.zip',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameCard(
              game: game,
              onDownload: () {},
              onLaunch: () {},
            ),
          ),
        ),
      ),
    );

    // Verify that we can find an ExcludeSemantics whose child is a MouseRegion 
    // and that MouseRegion's child is a Card.
    final specificExcludeSemanticsFinder = find.byWidgetPredicate((widget) {
      if (widget is! ExcludeSemantics) return false;
      final child = widget.child;
      return child is MouseRegion && child.child is Card;
    });

    expect(specificExcludeSemanticsFinder, findsOneWidget);
  });
}
