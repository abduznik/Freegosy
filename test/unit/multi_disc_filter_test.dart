import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/ui/widgets/multi_disc_picker.dart';

void main() {
  group('MultiDiscPicker.filterLaunchableFiles', () {
    test('filters out .m3u files', () {
      final files = [
        {'file_name': 'Game.m3u', 'file_size_bytes': 100},
        {'file_name': 'Game.nsp', 'file_size_bytes': 1000000},
      ];
      final result = MultiDiscPicker.filterLaunchableFiles(files);
      expect(result.length, 1);
      expect(result[0]['file_name'], 'Game.nsp');
    });

    test('filters out .cue files', () {
      final files = [
        {'file_name': 'Game.cue', 'file_size_bytes': 100},
        {'file_name': 'Game.bin', 'file_size_bytes': 1000000},
      ];
      final result = MultiDiscPicker.filterLaunchableFiles(files);
      expect(result.length, 1);
      expect(result[0]['file_name'], 'Game.bin');
    });

    test('filters out .ccd files', () {
      final files = [
        {'file_name': 'Game.ccd', 'file_size_bytes': 100},
        {'file_name': 'Game.img', 'file_size_bytes': 1000000},
      ];
      final result = MultiDiscPicker.filterLaunchableFiles(files);
      expect(result.length, 1);
    });

    test('filters out .mds files', () {
      final files = [
        {'file_name': 'Game.mds', 'file_size_bytes': 100},
        {'file_name': 'Game.iso', 'file_size_bytes': 1000000},
      ];
      final result = MultiDiscPicker.filterLaunchableFiles(files);
      expect(result.length, 1);
    });

    test('filters out .toc files', () {
      final files = [
        {'file_name': 'Game.toc', 'file_size_bytes': 100},
        {'file_name': 'Game.chd', 'file_size_bytes': 1000000},
      ];
      final result = MultiDiscPicker.filterLaunchableFiles(files);
      expect(result.length, 1);
    });

    test('filters out .xml files', () {
      final files = [
        {'file_name': 'Game.xml', 'file_size_bytes': 100},
        {'file_name': 'Game.nro', 'file_size_bytes': 1000000},
      ];
      final result = MultiDiscPicker.filterLaunchableFiles(files);
      expect(result.length, 1);
    });

    test('filters out .txt files', () {
      final files = [
        {'file_name': 'readme.txt', 'file_size_bytes': 100},
        {'file_name': 'Game.nsp', 'file_size_bytes': 1000000},
      ];
      final result = MultiDiscPicker.filterLaunchableFiles(files);
      expect(result.length, 1);
    });

    test('keeps .nsp files', () {
      final files = [
        {'file_name': 'Game.nsp', 'file_size_bytes': 1000000},
      ];
      final result = MultiDiscPicker.filterLaunchableFiles(files);
      expect(result.length, 1);
    });

    test('keeps .iso files', () {
      final files = [
        {'file_name': 'Game.iso', 'file_size_bytes': 1000000},
      ];
      final result = MultiDiscPicker.filterLaunchableFiles(files);
      expect(result.length, 1);
    });

    test('keeps .gba files', () {
      final files = [
        {'file_name': 'Game.gba', 'file_size_bytes': 1000000},
      ];
      final result = MultiDiscPicker.filterLaunchableFiles(files);
      expect(result.length, 1);
    });

    test('empty list returns empty', () {
      final result = MultiDiscPicker.filterLaunchableFiles([]);
      expect(result, isEmpty);
    });

    test('all non-launchable returns empty', () {
      final files = [
        {'file_name': 'Game.m3u', 'file_size_bytes': 100},
        {'file_name': 'Game.cue', 'file_size_bytes': 100},
      ];
      final result = MultiDiscPicker.filterLaunchableFiles(files);
      expect(result, isEmpty);
    });

    test('mixed launchable and non-launchable filters correctly', () {
      final files = [
        {'file_name': 'Game.m3u', 'file_size_bytes': 100},
        {'file_name': 'Game.nsp', 'file_size_bytes': 1000000},
        {'file_name': 'Game.cue', 'file_size_bytes': 100},
        {'file_name': 'Game.iso', 'file_size_bytes': 5000000},
      ];
      final result = MultiDiscPicker.filterLaunchableFiles(files);
      expect(result.length, 2);
      expect(result[0]['file_name'], 'Game.nsp');
      expect(result[1]['file_name'], 'Game.iso');
    });
  });
}
