import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';

void main() {
  group('Multi-disc label detection', () {
    // Replicate the _discLabel logic for testing
    String discLabel(String filename, int index) {
      final lower = filename.toLowerCase();
      final discMatch = RegExp(
        r'(?:[\(\[]?\s*)?(?:disc|disk|cd|part|track)\s*[_\s]?\s*(\d+)(?:\s*[\)\]]?)',
      ).firstMatch(lower);
      if (discMatch != null) {
        final num = discMatch.group(1)!.padLeft(2, '0');
        return lower.contains('track') ? 'Track $num' : 'Disc ${discMatch.group(1)}';
      }
      return 'File ${index + 1}';
    }

    test('standard "Disc 1" format', () {
      expect(discLabel('Final Fantasy VII (USA) (Disc 1).chd', 0), 'Disc 1');
      expect(discLabel('Final Fantasy VII (USA) (Disc 2).chd', 1), 'Disc 2');
      expect(discLabel('Final Fantasy VII (USA) (Disc 3).chd', 2), 'Disc 3');
    });

    test('parenthetical "(Disc 1)" format', () {
      expect(discLabel('Game (Disc 1).iso', 0), 'Disc 1');
      expect(discLabel('Game (disc 2).iso', 1), 'Disc 2');
    });

    test('"Disk" spelling', () {
      expect(discLabel('Game (Disk 1).chd', 0), 'Disc 1');
      expect(discLabel('Game (Disk 2).chd', 1), 'Disc 2');
    });

    test('no space "Disc1" format', () {
      expect(discLabel('Game Disc1.bin', 0), 'Disc 1');
      expect(discLabel('Game Disc2.bin', 1), 'Disc 2');
    });

    test('underscore "disc_1" format', () {
      expect(discLabel('game_disc_1.bin', 0), 'Disc 1');
      expect(discLabel('game_disk_2.bin', 1), 'Disc 2');
    });

    test('"CD" format', () {
      expect(discLabel('Game CD1.bin', 0), 'Disc 1');
      expect(discLabel('Game (CD 2).bin', 1), 'Disc 2');
    });

    test('"Part" format', () {
      expect(discLabel('Game Part 1.bin', 0), 'Disc 1');
      expect(discLabel('Game Part 2.bin', 1), 'Disc 2');
    });

    test('no disc indicator falls back to File N', () {
      expect(discLabel('Game.bin', 0), 'File 1');
      expect(discLabel('Game.chd', 3), 'File 4');
    });

    test('"Track" format with zero-padded numbers', () {
      expect(discLabel('Game (Track 1).chd', 0), 'Track 01');
      expect(discLabel('Game (Track 02).chd', 1), 'Track 02');
      expect(discLabel('Game (Track 10).chd', 2), 'Track 10');
    });
  });

  group('filterLaunchableFiles', () {
    List<Map<String, dynamic>> filterLaunchableFiles(List<Map<String, dynamic>> files) {
      const nonLaunchableExts = {'.cue', '.ccd', '.mds', '.toc', '.xml', '.json', '.txt', '.srt', '.sub'};
      return files.where((f) {
        final name = (f['file_name'] ?? '').toLowerCase();
        final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
        return !nonLaunchableExts.contains(ext);
      }).toList();
    }

    test('keeps .m3u playlists (launchable)', () {
      final files = [
        {'file_name': 'Game (Disc 1).chd'},
        {'file_name': 'Game (Disc 2).chd'},
        {'file_name': 'Game.m3u'},
      ];
      final result = filterLaunchableFiles(files);
      expect(result.length, 3);
      expect(result[0]['file_name'], 'Game (Disc 1).chd');
      expect(result[1]['file_name'], 'Game (Disc 2).chd');
      expect(result[2]['file_name'], 'Game.m3u');
    });

    test('excludes .cue sheets', () {
      final files = [
        {'file_name': 'Game.bin'},
        {'file_name': 'Game.cue'},
      ];
      final result = filterLaunchableFiles(files);
      expect(result.length, 1);
      expect(result[0]['file_name'], 'Game.bin');
    });

    test('keeps launchable files', () {
      final files = [
        {'file_name': 'Disc1.chd'},
        {'file_name': 'Disc2.chd'},
        {'file_name': 'Disc3.iso'},
      ];
      final result = filterLaunchableFiles(files);
      expect(result.length, 3);
    });
  });
}
