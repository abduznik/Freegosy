import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ROM name sanitization', () {
    test('exclamation mark is stripped', () {
      final name = 'Doki Doki Literature Club Plus!';
      final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?!]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      expect(sanitized, 'Doki Doki Literature Club Plus');
    });

    test('angle brackets are stripped', () {
      final name = 'Game <Special> Edition';
      final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?!]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      expect(sanitized, 'Game Special Edition');
    });

    test('colons are stripped', () {
      final name = 'Game: The Sequel';
      final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?!]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      expect(sanitized, 'Game The Sequel');
    });

    test('question marks are stripped', () {
      final name = 'What? Game?';
      final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?!]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      expect(sanitized, 'What Game');
    });

    test('multiple spaces are collapsed', () {
      final name = 'Game   With   Spaces';
      final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?!]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      expect(sanitized, 'Game With Spaces');
    });

    test('leading and trailing spaces are trimmed', () {
      final name = '  Game  ';
      final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?!]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      expect(sanitized, 'Game');
    });

    test('normal names pass through unchanged', () {
      final name = 'Super Mario World';
      final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?!]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      expect(sanitized, 'Super Mario World');
    });

    test('names with region tags are preserved', () {
      final name = 'Game (USA)';
      final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?!]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      expect(sanitized, 'Game (USA)');
    });

    test('names with brackets are preserved', () {
      final name = 'Game [Rev 1]';
      final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?!]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      expect(sanitized, 'Game [Rev 1]');
    });
  });

  group('Stem-prefix matching', () {
    test('exact match works', () {
      expect('game.gba'.startsWith('game'), isTrue);
    });

    test('prefix with region tag matches', () {
      expect('game (usa).gba'.startsWith('game'), isTrue);
    });

    test('prefix with version tag matches', () {
      expect('game (v1.0).gba'.startsWith('game'), isTrue);
    });

    test('different name does not match', () {
      expect('other.gba'.startsWith('game'), isFalse);
    });

    test('case insensitive matching', () {
      expect('GAME (USA).gba'.toLowerCase().startsWith('game'), isTrue);
    });
  });
}
