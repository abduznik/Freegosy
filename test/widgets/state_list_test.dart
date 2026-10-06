import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/resume_service.dart';
import 'package:freegosy/core/save/save_state_info.dart';
import 'package:freegosy/ui/widgets/save_list/state_list.dart';

void main() {
  ResumeEntry state(int slot) => ResumeEntry(
      emulatorId: 'ares', emulatorName: 'ares', fileName: 's$slot', slot: NumberedStateSlot(slot),
      savedAt: DateTime(2026, 9, slot), where: ResumeWhere.thisPc);

  testWidgets('states are listed by slot and picking one reports it', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: Scaffold(body: StateList(states: [state(1), state(2)], onSelect: (s) => picked.add(s.fileName))))));
    expect(find.text('Slot 1'), findsOneWidget);
    await tester.tap(find.text('Slot 2'));
    expect(picked, ['s2']);
  });

  testWidgets('no states says so', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: Scaffold(body: StateList(states: [], onSelect: _noop)))));
    expect(find.text('No save states'), findsOneWidget);
  });
}

void _noop(ResumeEntry _) {}
