import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/resume_service.dart';
import 'package:freegosy/core/save/save_state_info.dart';
import 'package:freegosy/ui/widgets/game_detail/resume_split_button.dart';

void main() {
  final entry = ResumeEntry(
    emulatorId: 'emu',
    emulatorName: 'Emu',
    fileName: 'a.st',
    slot: const AutoStateSlot(),
    savedAt: DateTime(2026, 9, 21, 21, 10),
    where: ResumeWhere.thisPc,
  );

  /// The focus border's corner radii drawn by the FocusEffectWrapper behind [key].
  BorderRadiusGeometry? focusBorderRadius(WidgetTester tester, Key key) {
    final container = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byKey(key), matching: find.byType(AnimatedContainer)).first);
    return (container.decoration as BoxDecoration?)?.borderRadius;
  }

  testWidgets('each half draws its focus border with its own corners, not four rounded ones',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ResumeSplitButton(
            newest: entry,
            focusNode: FocusNode(),
            onResume: () {},
            onOpenSlots: () {},
          ),
        ),
      ),
    ));

    expect(focusBorderRadius(tester, const Key('resume-main')),
        const BorderRadius.horizontal(left: Radius.circular(16)));
    expect(focusBorderRadius(tester, const Key('resume-slots')),
        const BorderRadius.horizontal(right: Radius.circular(16)));
  });
}
