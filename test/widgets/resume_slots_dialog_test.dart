import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/resume_service.dart';
import 'package:freegosy/core/save/save_state_info.dart';
import 'package:freegosy/ui/widgets/game_detail/resume_slots_dialog.dart';

/// Hosts the dialog behind a button, plus a way to force the host to rebuild
/// (`setState` reached via [tester.state], since the modal barrier blocks
/// taps on anything behind the open dialog) without touching the dialog
/// itself — this is what used to recreate every row's thumbnail future.
class _Harness extends StatefulWidget {
  const _Harness({required this.entries, required this.thumbnailFor});
  final List<ResumeEntry> entries;
  final Future<Uint8List?> Function(ResumeEntry entry) thumbnailFor;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int rebuilds = 0;

  /// Forces this ancestor of the dialog's Overlay to rebuild, without the
  /// test reaching into the protected `setState`.
  void forceRebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showResumeSlotsDialog(context, widget.entries, thumbnailFor: widget.thumbnailFor),
              child: Text('open $rebuilds'),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  final entries = [
    ResumeEntry(
      emulatorId: 'emu',
      emulatorName: 'Emu',
      fileName: 'a.st',
      slot: const AutoStateSlot(),
      savedAt: DateTime(2026, 1, 1),
      where: ResumeWhere.thisPc,
    ),
    ResumeEntry(
      emulatorId: 'emu',
      emulatorName: 'Emu',
      fileName: 'b.st',
      slot: const NumberedStateSlot(1),
      savedAt: DateTime(2026, 1, 2),
      where: ResumeWhere.thisPc,
    ),
  ];

  testWidgets('each row fetches its thumbnail once, even when the dialog is rebuilt', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_Harness(
      entries: entries,
      thumbnailFor: (e) async {
        calls++;
        return null;
      },
    ));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(calls, entries.length);

    // Force the host (an ancestor of the dialog's Overlay) to rebuild, which
    // used to recreate every row's thumbnail future and refetch.
    tester.state<_HarnessState>(find.byType(_Harness)).forceRebuild();
    await tester.pumpAndSettle();

    expect(calls, entries.length, reason: 'the thumbnail future must not be recreated on rebuild');
  });

  testWidgets('the first row autofocuses', (tester) async {
    await tester.pumpWidget(_Harness(entries: entries, thumbnailFor: (e) async => null));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(find.text('Resume (saved on exit)'), findsOneWidget);
    expect(find.text('Slot 1'), findsOneWidget);
  });

  testWidgets(
      'with two emulators, the name is not repeated when the version line already names it, '
      'but is kept for a version-unknown row', (tester) async {
    final twoEmuEntries = [
      ResumeEntry(
        emulatorId: 'emuA',
        emulatorName: 'EmuA',
        fileName: 'a.st',
        slot: const AutoStateSlot(),
        savedAt: DateTime(2026, 1, 1),
        where: ResumeWhere.thisPc,
        emulatorVersion: 'v2.8.2',
      ),
      ResumeEntry(
        emulatorId: 'emuB',
        emulatorName: 'EmuB',
        fileName: 'b.st',
        slot: const NumberedStateSlot(1),
        savedAt: DateTime(2026, 1, 2),
        where: ResumeWhere.thisPc,
      ),
    ];
    await tester.pumpWidget(_Harness(entries: twoEmuEntries, thumbnailFor: (e) async => null));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('1 Jan 00:00 · EmuA v2.8.2 · this PC'), findsOneWidget);
    expect(find.text('2 Jan 00:00 · version unknown · this PC · EmuB'), findsOneWidget);
  });
}
