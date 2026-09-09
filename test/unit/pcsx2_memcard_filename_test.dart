import 'package:flutter_test/flutter_test.dart';

/// Reimplementation of Pcsx2SaveStrategy._normalizeMemcardFilename for testing.
/// Source: lib/core/save/strategies/pcsx2_save_strategy.dart:78-88
///
/// NOTE: serial normalization/extraction moved to SerialExtractionService
/// and is tested directly (against the real implementation) in
/// test/unit/serial_extraction_service_test.dart.
String normalizeMemcardFilename(String filename) {
  if (!filename.toLowerCase().endsWith('.ps2')) return filename;
  final match = RegExp(r'^(Mcd\d+)', caseSensitive: false).firstMatch(filename);
  if (match != null) {
    return '${match.group(1)}.ps2';
  }
  return filename;
}

void main() {
  group('PCSX2 memcard filename normalization', () {
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
  });
}
