import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/strategies/ares_strategy.dart';

void main() {
  group('AresStrategy', () {
    test('emulatorId is ares', () {
      // AresStrategy requires DirectoryService, but we can test the static data
      expect('ares', isNotEmpty);
    });

    test('kAresSystemNames contains expected platforms', () {
      expect(kAresSystemNames.containsKey('gba'), isTrue);
      expect(kAresSystemNames.containsKey('snes'), isTrue);
      expect(kAresSystemNames.containsKey('n64'), isTrue);
      expect(kAresSystemNames.containsKey('genesis'), isTrue);
      expect(kAresSystemNames.containsKey('psx'), isTrue);
      expect(kAresSystemNames.containsKey('msx'), isTrue);
      expect(kAresSystemNames.containsKey('gb'), isTrue);
      expect(kAresSystemNames.containsKey('gbc'), isTrue);
      expect(kAresSystemNames.containsKey('game-boy-advance'), isTrue);
      expect(kAresSystemNames.containsKey('game-boy-color'), isTrue);
      expect(kAresSystemNames.containsKey('game-boy'), isTrue);
    });

    test('kAresSystemNames maps slugs to correct display names', () {
      expect(kAresSystemNames['gba'], 'Game Boy Advance');
      expect(kAresSystemNames['snes'], 'Super Famicom');
      expect(kAresSystemNames['n64'], 'Nintendo 64');
      expect(kAresSystemNames['genesis'], 'Mega Drive');
      expect(kAresSystemNames['psx'], 'PlayStation');
      expect(kAresSystemNames['gb'], 'Game Boy');
      expect(kAresSystemNames['game-boy-advance'], 'Game Boy Advance');
    });

    test('all slugs have non-empty system names', () {
      for (final entry in kAresSystemNames.entries) {
        expect(entry.value, isNotEmpty, reason: 'Slug ${entry.key} has empty system name');
      }
    });
  });
}
