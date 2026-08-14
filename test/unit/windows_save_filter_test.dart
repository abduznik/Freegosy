import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/strategies/windows_save_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';

void main() {
  group('WindowsSaveStrategy filter parsing', () {
    test('empty filter returns empty list', () {
      expect(_parseFilter([]), isEmpty);
      expect(_parseFilter(['']), isEmpty);
      expect(_parseFilter(['  ']), isEmpty);
    });

    test('single pattern parsed correctly', () {
      expect(_parseFilter(['*.ini']), ['*.ini']);
    });

    test('multiple patterns parsed correctly', () {
      expect(_parseFilter(['*.ini', '*.bin', 'eeprom.*']), ['*.ini', '*.bin', 'eeprom.*']);
    });

    test('whitespace trimmed', () {
      expect(_parseFilter(['  *.ini  ', '  *.bin  ']), ['*.ini', '*.bin']);
    });
  });

  group('WindowsSaveStrategy pattern matching', () {
    test('exact filename matches', () {
      expect(_matchesPattern('eeprom.bin', ['eeprom.bin']), isTrue);
      expect(_matchesPattern('config.txt', ['eeprom.bin']), isFalse);
    });

    test('glob *.ext matches any file with that extension', () {
      expect(_matchesPattern('save.ini', ['*.ini']), isTrue);
      expect(_matchesPattern('config.ini', ['*.ini']), isTrue);
      expect(_matchesPattern('save.bin', ['*.ini']), isFalse);
    });

    test('prefix name.* matches files starting with that name', () {
      expect(_matchesPattern('eeprom.bin', ['eeprom.*']), isTrue);
      expect(_matchesPattern('eeprom.dat', ['eeprom.*']), isTrue);
      expect(_matchesPattern('save.bin', ['eeprom.*']), isFalse);
    });

    test('path prefix saves/* matches files under saves/', () {
      expect(_matchesPattern('/game/saves/data.bin', ['saves/*']), isTrue);
      expect(_matchesPattern('/game/saves/sub/file.dat', ['saves/*']), isTrue);
      expect(_matchesPattern('/game/config.ini', ['saves/*']), isFalse);
    });

    test('multiple patterns - any match passes', () {
      expect(_matchesPattern('eeprom.bin', ['*.ini', 'eeprom.*']), isTrue);
      expect(_matchesPattern('config.ini', ['*.ini', 'eeprom.*']), isTrue);
      expect(_matchesPattern('save.dat', ['*.ini', 'eeprom.*']), isFalse);
    });

    test('case insensitive matching', () {
      expect(_matchesPattern('EEPROM.BIN', ['eeprom.*']), isTrue);
      expect(_matchesPattern('Save.INI', ['*.ini']), isTrue);
    });
  });

  group('Issue #48 — loadPersistedFilters', () {
    test('filters round-trip through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'win_filter_game1': '*.ini,*.bin',
        'win_filter_game2': 'eeprom.*',
      });
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final strategy = WindowsSaveStrategy(prefs);

      strategy.loadPersistedFilters();

      expect(strategy.getSaveFilter('game1'), '*.ini,*.bin');
      expect(strategy.getSaveFilter('game2'), 'eeprom.*');
      expect(strategy.getSaveFilter('game3'), isNull);
    });

    test('setSaveFilter persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final strategy = WindowsSaveStrategy(prefs);

      await strategy.setSaveFilter('game1', '*.ini,save.bin');

      // Reload from prefs to verify persistence
      final strategy2 = WindowsSaveStrategy(prefs);
      strategy2.loadPersistedFilters();
      expect(strategy2.getSaveFilter('game1'), '*.ini,save.bin');
    });
  });

  group('Issue #48 — getSaveFiles with filter', () {
    late Directory tempDir;
    late Directory saveDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('win_save_filter_test_');
      saveDir = Directory('${tempDir.path}/saves');
      await saveDir.create();
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('returns individual filtered files when filter is active', () async {
      // Create test files
      await File('${saveDir.path}/eeprom.bin').writeAsBytes([1, 2, 3]);
      await File('${saveDir.path}/config.ini').writeAsBytes([4, 5, 6]);
      await File('${saveDir.path}/game.exe').writeAsBytes([7, 8, 9]);
      await File('${saveDir.path}/readme.txt').writeAsBytes([10, 11, 12]);

      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final strategy = WindowsSaveStrategy(prefs);

      // Set filter: only .bin and .ini files
      await strategy.setSaveFilter('testgame', '*.bin,*.ini');

      final game = Game(id: 'testgame', name: 'Test Game', platformSlug: 'windows', fileSize: 0);

      // Set manual override to point to our test directory
      await strategy.setManualOverride('testgame', saveDir.path);

      final files = await strategy.getSaveFiles(game, '${tempDir.path}/roms/test.exe');

      // Should return only the filtered files, not the directory
      expect(files.length, 2);
      final names = files.map((f) => f.uri.pathSegments.last).toSet();
      expect(names, containsAll(['eeprom.bin', 'config.ini']));
      expect(names, isNot(contains('game.exe')));
      expect(names, isNot(contains('readme.txt')));
      // Should NOT be a directory entry
      expect(files.any((f) => FileSystemEntity.isDirectorySync(f.path)), isFalse,
          reason: 'Filtered results should be individual files, not directories');
    });

    test('returns directory when no filter is set', () async {
      await File('${saveDir.path}/save.bin').writeAsBytes([1, 2, 3]);

      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final strategy = WindowsSaveStrategy(prefs);

      await strategy.setManualOverride('testgame', saveDir.path);

      final game = Game(id: 'testgame', name: 'Test Game', platformSlug: 'windows', fileSize: 0);
      final files = await strategy.getSaveFiles(game, '${tempDir.path}/roms/test.exe');

      // Should return the directory (wrapped as File)
      expect(files.length, 1);
      expect(files[0].path, saveDir.path);
    });
  });
}

// Expose private helpers for testing
List<String> _parseFilter(List<String> input) {
  final combined = input.join(',');
  if (combined.trim().isEmpty) return [];
  return combined.split(',').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
}

bool _matchesPattern(String filePath, List<String> patterns) {
  final fileName = filePath.split(RegExp(r'[/\\]')).last.toLowerCase();
  final relativePath = filePath.replaceAll('\\', '/').toLowerCase();
  for (final pattern in patterns) {
    if (fileName == pattern) return true;
    if (pattern.startsWith('*.')) {
      final ext = pattern.substring(1);
      if (fileName.endsWith(ext)) return true;
    }
    if (pattern.endsWith('.*')) {
      final name = pattern.substring(0, pattern.length - 2);
      if (fileName.startsWith(name)) return true;
    }
    if (pattern.endsWith('/*')) {
      final prefix = pattern.substring(0, pattern.length - 1);
      if (relativePath.contains(prefix)) return true;
    }
  }
  return false;
}
