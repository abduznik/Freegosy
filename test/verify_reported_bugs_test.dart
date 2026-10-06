import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/ui/widgets/game_detail/game_metadata_chip.dart';
import 'package:freegosy/ui/widgets/screenshot_gallery_dialog.dart';
import 'package:freegosy/ui/widgets/game_detail/game_action_button.dart';

void main() {
  group('BUG 1: GameMetadataChip — RenderFlex overflow on long label', () {
    testWidgets('short label renders fine', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GameMetadataChip(label: 'Action', icon: Icons.star)),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Action'), findsOneWidget);
    });

    testWidgets('long label no longer overflows (fixed: Flexible + ellipsis)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GameMetadataChip(label: 'A' * 200, icon: Icons.star)),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('GameActionButton handles same length correctly (no overflow)', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameActionButton(icon: Icons.star, label: 'A' * 200, onPressed: () {}),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('BUG 3: ScreenshotGalleryDialog — empty image list shows "1 / 0"', () {
    testWidgets('renders without crash when imageUrls is empty', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScreenshotGalleryDialog(initialIndex: 0, imageUrls: const []),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no indicator shown for empty image list (fixed)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScreenshotGalleryDialog(initialIndex: 0, imageUrls: const []),
      ));

      expect(find.textContaining('/'), findsNothing);
    });

    testWidgets('single image shows "1 / 1" correctly', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScreenshotGalleryDialog(
          initialIndex: 0,
          imageUrls: const ['https://example.com/screenshot.png'],
        ),
      ));
      // For a single image, (0 + 1) / 1 = "1 / 1" — correct
      expect(find.text('1 / 1'), findsOneWidget);
    });
  });
}
