import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/providers/library_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/ui/widgets/cover_size_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CoverSizeButton step mapping', () {
    test('slider runs small covers (many columns) to large covers (few columns)', () {
      expect(CoverSizeButton.columnCountFor(0), kMaxColumnCount);
      expect(CoverSizeButton.columnCountFor(kMaxColumnCount - kMinColumnCount), kMinColumnCount);
    });

    test('step and column count round-trip across the whole range', () {
      for (var columns = kMinColumnCount; columns <= kMaxColumnCount; columns++) {
        expect(CoverSizeButton.columnCountFor(CoverSizeButton.sizeStepFor(columns)), columns);
      }
    });

    test('out-of-range stored column counts are clamped', () {
      expect(CoverSizeButton.sizeStepFor(40), 0);
      expect(CoverSizeButton.sizeStepFor(0), kMaxColumnCount - kMinColumnCount);
    });
  });

  testWidgets('opens the cover size dialog showing the current games per row', (tester) async {
    SharedPreferences.setMockInitialValues({'column_count': 5});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: Scaffold(body: CoverSizeButton())),
    ));

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('Cover size'), findsOneWidget);
    expect(find.text('5 games per row'), findsOneWidget);
  });
}
