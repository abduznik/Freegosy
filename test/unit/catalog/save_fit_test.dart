import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/catalog/save_entry.dart';
import 'package:freegosy/core/save/catalog/save_fit.dart';
import 'package:freegosy/core/save/catalog/save_maker.dart';

void main() {
  const ares = SaveMaker('ares');
  const mupen = SaveMaker('retroarch', coreId: 'mupen64plus_next');
  const parallel = SaveMaker('retroarch', coreId: 'parallel_n64');
  const duck = SaveMaker('duckstation');
  const rearmed = SaveMaker('retroarch', coreId: 'pcsx_rearmed');
  final when = DateTime(2026, 10, 1);

  SaveEntry save(SaveMaker? maker) =>
      SaveEntry(source: SaveSource.romm, fileName: 'x', savedAt: when, maker: maker, tag: maker?.tag ?? 'freegosy');

  SaveFit n64(SaveEntry e, {SaveMaker? picked, Set<String> installed = const {'ares', 'retroarch'}}) =>
      fitFor(e, platformSlug: 'n64', picked: picked, platformDefault: mupen, installed: installed);

  group('with an emulator picked', () {
    test('its own saves are native', () {
      expect(n64(save(ares), picked: ares).kind, SaveFitKind.native);
      expect(n64(save(ares), picked: ares).playsIn, ares);
    });

    test('another RetroArch core of the same format is native', () {
      expect(n64(save(parallel), picked: mupen).kind, SaveFitKind.native);
    });

    test('N64 saves no longer convert between ares and RetroArch', () {
      expect(n64(save(mupen), picked: ares).kind, SaveFitKind.unusable);
      expect(n64(save(ares), picked: mupen).kind, SaveFitKind.unusable);
    });

    test('a PS1 card from DuckStation converts for a RetroArch core', () {
      final fit = fitFor(save(duck), platformSlug: 'psx', picked: rearmed, platformDefault: rearmed, installed: const {'retroarch', 'duckstation'});
      expect(fit.kind, SaveFitKind.converted);
    });

    test('a RetroArch PS1 card fits DuckStation, converted to its card', () {
      final fit = fitFor(save(rearmed), platformSlug: 'psx', picked: duck, platformDefault: rearmed, installed: const {'retroarch', 'duckstation'});
      expect(fit.kind, SaveFitKind.converted);
    });

    test('a save no format converts into the picked emulator\'s is unusable, with the reason', () {
      final fit = fitFor(save(ares), platformSlug: 'n64', picked: mupen, platformDefault: mupen, installed: const {'retroarch', 'ares'});
      expect(fit.kind, SaveFitKind.unusable);
      expect(fit.reason, contains('retroarch'));
    });

    test('an unknown maker is shown and plays in the picked emulator', () {
      final fit = n64(save(null), picked: ares);
      expect(fit.kind, SaveFitKind.unknownMaker);
      expect(fit.playsIn, ares);
      expect(fit.usable, isTrue);
    });
  });

  group('saves on this PC', () {
    SaveEntry local(SaveSource source, SaveMaker maker) =>
        SaveEntry(source: source, fileName: 'x', savedAt: when, maker: maker, tag: maker.tag);

    test('a RetroArch save of another core is unusable in this core, with the reason', () {
      final fit = n64(local(SaveSource.local, parallel), picked: mupen);
      expect(fit.kind, SaveFitKind.unusable);
      expect(fit.reason, contains('parallel_n64'));
    });

    test('a RetroArch backup goes back only into the core it was made with', () {
      expect(n64(local(SaveSource.backup, mupen), picked: parallel).kind, SaveFitKind.unusable);
      expect(n64(local(SaveSource.backup, mupen), picked: mupen).kind, SaveFitKind.native);
    });

    test('an older RetroArch backup without a core goes back into RetroArch, any core', () {
      const retroarchOnly = SaveMaker('retroarch');
      expect(n64(local(SaveSource.backup, retroarchOnly), picked: parallel).kind, SaveFitKind.native);
      expect(n64(local(SaveSource.backup, retroarchOnly), picked: ares).kind, SaveFitKind.unusable);
    });

    test('a backup goes back only into the emulator it was made for', () {
      expect(n64(local(SaveSource.backup, mupen), picked: ares).kind, SaveFitKind.unusable);
      expect(n64(local(SaveSource.backup, ares), picked: ares).kind, SaveFitKind.native);
    });

    test('another emulator\'s local save still converts (PS1 card)', () {
      final fit = fitFor(local(SaveSource.local, duck), platformSlug: 'psx', picked: rearmed, platformDefault: rearmed,
          installed: const {'retroarch', 'duckstation'});
      expect(fit.kind, SaveFitKind.converted);
    });
  });

  group('with Any', () {
    test('a save plays in the installed emulator that made it, native', () {
      expect(n64(save(ares)).kind, SaveFitKind.native);
      expect(n64(save(ares)).playsIn, ares);
      expect(n64(save(mupen)).playsIn, mupen);
    });

    test('a save whose maker is not installed and can\'t convert is unusable', () {
      final fit = n64(save(ares), installed: const {'retroarch'});
      expect(fit.kind, SaveFitKind.unusable);
    });

    test('an unknown maker plays in the platform default', () {
      expect(n64(save(null)).playsIn, mupen);
    });

    test('with nothing installed for the platform, every save is unusable', () {
      final fit = fitFor(save(ares), platformSlug: 'n64', picked: null, platformDefault: null, installed: const {});
      expect(fit.kind, SaveFitKind.unusable);
      expect(fit.reason, isNotNull);
    });
  });

  group('a tag that is both a standalone emulator and a RetroArch core', () {
    // RetroArch uploads with the bare core name; RomM can't tell the two apart.
    for (final name in ['mgba', 'melonds', 'pcsx2', 'ppsspp', 'azahar', 'flycast', 'mame']) {
      test('$name: a RomM save fits RetroArch\'s $name core and standalone $name', () {
        final e = save(SaveMaker(name)); // how resolveSaveMaker reads the tag
        final core = SaveMaker('retroarch', coreId: name);
        expect(fitFor(e, platformSlug: 'x', picked: core, platformDefault: core, installed: {'retroarch', name}).kind,
            SaveFitKind.native);
        expect(fitFor(e, platformSlug: 'x', picked: SaveMaker(name), platformDefault: core, installed: {'retroarch', name}).kind,
            SaveFitKind.native);
      });
    }

    test('a local RetroArch save is not moved to the standalone emulator by its name alone', () {
      final e = SaveEntry(source: SaveSource.local, fileName: 'x', savedAt: when,
          maker: const SaveMaker('retroarch', coreId: 'mgba'), tag: 'mgba');
      expect(fitFor(e, platformSlug: 'x', picked: const SaveMaker('mgba'), platformDefault: null, installed: const {'retroarch', 'mgba'}).kind,
          SaveFitKind.unusable);
    });
  });
}
