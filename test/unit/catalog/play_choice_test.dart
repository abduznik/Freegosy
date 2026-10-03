import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/catalog/play_choice.dart';
import 'package:freegosy/core/save/catalog/save_entry.dart';
import 'package:freegosy/core/save/catalog/save_fit.dart';
import 'package:freegosy/core/save/catalog/save_maker.dart';
import 'package:freegosy/core/save/resume_service.dart';
import 'package:freegosy/core/save/save_state_info.dart';

void main() {
  const ares = SaveMaker('ares');
  SavePlay save(DateTime t, {SaveSource source = SaveSource.romm, bool usable = true}) => SavePlay(
        SaveEntry(source: source, fileName: 's', savedAt: t, maker: ares),
        usable ? const SaveFit(SaveFitKind.native, playsIn: ares) : const SaveFit(SaveFitKind.unusable, reason: 'no'),
      );
  StatePlay state(DateTime t) => StatePlay(ResumeEntry(
        emulatorId: 'ares',
        emulatorName: 'ares',
        fileName: 'g.state1',
        slot: const NumberedStateSlot(1),
        savedAt: t,
        where: ResumeWhere.thisPc,
      ));
  final mon = DateTime(2026, 9, 28), tue = DateTime(2026, 9, 29), wed = DateTime(2026, 9, 30);

  group('preselect', () {
    test('the newest usable save', () {
      final picked = preselect([save(mon), save(wed), save(tue)], const []);
      expect(picked!.time, wed);
    });

    test('an unusable save is never preselected', () {
      final picked = preselect([save(wed, usable: false), save(mon)], const []);
      expect(picked!.time, mon);
    });

    test('a state only when it is newer than the newest save', () {
      expect(preselect([save(tue)], [state(wed)]), isA<StatePlay>());
      expect(preselect([save(wed)], [state(tue)]), isA<SavePlay>());
    });

    test('a state when there are no usable saves; nothing when there is nothing', () {
      expect(preselect(const [], [state(mon)]), isA<StatePlay>());
      expect(preselect(const [], const []), isNull);
    });
  });

  group('promptFor', () {
    test('a save older than the target\'s local save asks', () {
      expect(promptFor(save(mon), newestLocalOfTarget: tue), PlayPrompt.olderSave);
    });

    test('the newest save, or the local save itself, does not ask', () {
      expect(promptFor(save(wed), newestLocalOfTarget: tue), isNull);
      expect(promptFor(save(tue, source: SaveSource.local), newestLocalOfTarget: tue), isNull);
      expect(promptFor(save(mon), newestLocalOfTarget: null), isNull);
    });

    test('a state older than the newest save asks', () {
      expect(promptFor(state(mon), newestSave: tue), PlayPrompt.olderState);
      expect(promptFor(state(wed), newestSave: tue), isNull);
    });
  });
}
