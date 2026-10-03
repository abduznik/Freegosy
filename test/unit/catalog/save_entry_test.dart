import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/catalog/save_entry.dart';
import 'package:freegosy/core/save/catalog/save_maker.dart';

void main() {
  const ids = {'retroarch', 'ares'};

  test('a RomM save becomes a row with its maker, size, slot and time', () {
    final e = SaveEntry.fromRomm({
      'id': 7,
      'file_name': 'Mario Kart 64 (U) [!].srm',
      'emulator': 'mupen64plus_next',
      'file_size_bytes': 296960,
      'slot': 'freegosy',
      'updated_at': '2026-09-28T16:40:00Z',
    }, emulatorIds: ids);

    expect(e.source, SaveSource.romm);
    expect(e.fileName, 'Mario Kart 64 (U) [!].srm');
    expect(e.maker, const SaveMaker('retroarch', coreId: 'mupen64plus_next'));
    expect(e.tag, 'mupen64plus_next');
    expect(e.sizeBytes, 296960);
    expect(e.slot, 'freegosy');
    expect(e.savedAt, DateTime.utc(2026, 9, 28, 16, 40).toLocal());
    expect(e.rommSave!['id'], 7);
  });

  test('created_at is used when updated_at is missing, and odd fields are tolerated', () {
    final e = SaveEntry.fromRomm({
      'file_name': 'x.zip',
      'emulator': 'freegosy',
      'file_size_bytes': '218',
      'created_at': '2026-10-01T07:56:29Z',
    }, emulatorIds: ids);
    expect(e.maker, isNull);
    expect(e.tag, 'freegosy');
    expect(e.sizeBytes, 218);
    expect(e.savedAt, DateTime.utc(2026, 10, 1, 7, 56, 29).toLocal());
  });

  test('saves group by slot and tag', () {
    SaveEntry e(String slot, String tag) => SaveEntry.fromRomm(
        {'file_name': 'a', 'emulator': tag, 'slot': slot, 'updated_at': '2026-01-01T00:00:00Z'}, emulatorIds: ids);
    expect(e('freegosy', 'ares').groupKey, e('freegosy', 'ares').groupKey);
    expect(e('freegosy', 'ares').groupKey, isNot(e('freegosy', 'mupen64plus_next').groupKey));
    expect(e('a', 'ares').groupKey, isNot(e('b', 'ares').groupKey));
  });
}
