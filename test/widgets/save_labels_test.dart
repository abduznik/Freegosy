import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/ui/widgets/save_list/save_labels.dart';

void main() {
  test('sizes read like RomM\'s', () {
    expect(formatSaveSize(512), '512 B');
    expect(formatSaveSize(296960), '290.0 KB');
    expect(formatSaveSize(3 * 1024 * 1024 + 300 * 1024), '3.3 MB');
  });

  test('times say today, yesterday, a date, or a date with the year', () {
    final now = DateTime(2026, 10, 1, 12);
    expect(formatSaveTime(DateTime(2026, 10, 1, 9, 56), now: now), 'today 09:56');
    expect(formatSaveTime(DateTime(2026, 9, 30, 21, 12), now: now), 'yesterday 21:12');
    expect(formatSaveTime(DateTime(2026, 9, 28, 18, 40), now: now), '28 Sep 18:40');
    expect(formatSaveTime(DateTime(2025, 12, 24, 8, 0), now: now), '24 Dec 2025');
  });

  testWidgets('a chip shows its text', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SaveChip('ares', color: Colors.orange)));
    expect(find.text('ares'), findsOneWidget);
  });
}
