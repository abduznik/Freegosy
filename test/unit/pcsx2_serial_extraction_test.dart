import 'package:flutter_test/flutter_test.dart';

/// Reimplementation of Pcsx2SaveStrategy._normalizeSerial for testing.
/// Source: lib/core/save/strategies/pcsx2_save_strategy.dart:70-76
String normalizeSerial(String raw) {
  var s = raw.toUpperCase().replaceAll('_', '-');
  s = s.replaceAllMapped(RegExp(r'(\d{3})\.(\d{2})'), (m) => '${m[1]}${m[2]}');
  return s;
}

/// Reimplementation of Pcsx2SaveStrategy._normalizeMemcardFilename for testing.
/// Source: lib/core/save/strategies/pcsx2_save_strategy.dart:78-88
String normalizeMemcardFilename(String filename) {
  if (!filename.toLowerCase().endsWith('.ps2')) return filename;
  final match = RegExp(r'^(Mcd\d+)', caseSensitive: false).firstMatch(filename);
  if (match != null) {
    return '${match.group(1)}.ps2';
  }
  return filename;
}

/// Reimplementation of Pcsx2SaveStrategy._extractSerial filename regex for testing.
/// Source: lib/core/save/strategies/pcsx2_save_strategy.dart:34-38
String? extractSerialFromFilename(String romPath) {
  // Extract basename without extension
  final lastSlash = romPath.lastIndexOf('/');
  final lastDot = romPath.lastIndexOf('.');
  final base = lastDot > lastSlash
      ? romPath.substring(lastSlash + 1, lastDot)
      : romPath.substring(lastSlash + 1);

  final filenameMatch =
      RegExp(r'\b(S[A-Z]{3,4}[-_]\d{3}[\._]?\d{2})\b', caseSensitive: false)
          .firstMatch(base);
  if (filenameMatch != null) {
    return normalizeSerial(filenameMatch.group(1)!);
  }
  return null;
}

void main() {
  group('PCSX2 serial extraction and normalization', () {
    group('normalizeSerial', () {
      test('underscore separator to dash', () {
        expect(normalizeSerial('SLUS_12345'), 'SLUS-12345');
      });

      test('dot before digits removed', () {
        expect(normalizeSerial('SLUS-123.45'), 'SLUS-12345');
      });

      test('already normalized stays same', () {
        expect(normalizeSerial('SCUS-97113'), 'SCUS-97113');
      });

      test('lowercase converted to uppercase', () {
        expect(normalizeSerial('slus_12345'), 'SLUS-12345');
      });

      test('mixed case and separators', () {
        expect(normalizeSerial('SlUs_123.45'), 'SLUS-12345');
      });

      test('5-char prefix (SLUS_12345)', () {
        expect(normalizeSerial('SLPS_250.00'), 'SLPS-25000');
      });
    });

    group('normalizeMemcardFilename', () {
      test('strips timestamp suffix', () {
        expect(
          normalizeMemcardFilename('Mcd001 [2026-04-03_20-31-19].ps2'),
          'Mcd001.ps2',
        );
      });

      test('strips any bracket content', () {
        expect(
          normalizeMemcardFilename('Mcd002 [anything].ps2'),
          'Mcd002.ps2',
        );
      });

      test('non-timestamp file returns as-is', () {
        expect(normalizeMemcardFilename('Mcd001.ps2'), 'Mcd001.ps2');
      });

      test('non-.ps2 extension returns as-is', () {
        expect(normalizeMemcardFilename('Mcd001.sav'), 'Mcd001.sav');
      });

      test('non-matching pattern returns as-is', () {
        expect(normalizeMemcardFilename('CustomCard.ps2'), 'CustomCard.ps2');
      });

      test('case insensitive .PS2 extension', () {
        // The function checks .toLowerCase() but returns the original casing
        // for the Mcd prefix match, preserving the original .PS2 extension
        final result = normalizeMemcardFilename('Mcd001 [backup].PS2');
        // The function lowercases for comparison but the regex match preserves original
        expect(result.toLowerCase(), 'mcd001.ps2');
      });
    });

    group('extractSerialFromFilename', () {
      test('extracts SLUS-12345 pattern', () {
        expect(
          extractSerialFromFilename('/roms/ps2/Ico (SCUS-97113).iso'),
          'SCUS-97113',
        );
      });

      test('extracts with underscore separator', () {
        expect(
          extractSerialFromFilename('/roms/ps2/Game (SLUS_123.45).iso'),
          'SLUS-12345',
        );
      });

      test('extracts 5-char prefix', () {
        expect(
          extractSerialFromFilename('/roms/ps2/FFX (SLPS-250.00).iso'),
          'SLPS-25000',
        );
      });

      test('no match returns null', () {
        expect(
          extractSerialFromFilename('/roms/ps2/MyGame.iso'),
          isNull,
        );
      });

      test('serial at start of filename', () {
        expect(
          extractSerialFromFilename('/roms/ps2/SCUS-97113 - Ico.iso'),
          'SCUS-97113',
        );
      });
    });
  });
}
