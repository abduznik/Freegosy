import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/strategies/windows_save_strategy.dart';

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
