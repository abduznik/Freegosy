import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/emulator/strategies/ares_strategy.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';

/// Minimal mock that captures launchGame args for verification.
class _MockDirectoryService extends DirectoryService {
  List<String>? lastArgs;
  String? lastExePath;

  _MockDirectoryService(super.prefs);

  @override
  Future<String?> findEmulatorExecutable(String emulatorId, String executable) async {
    return '/fake/ares';
  }

  @override
  Future<void> launchGame(Game game, String romPath, String emulatorId, String exePath,
      {List<String> args = const []}) async {
    lastArgs = args;
    lastExePath = exePath;
  }

  @override
  Future<Process?> launchGameWithHandle(Game game, String romPath, String emulatorId,
      String exePath, {List<String> args = const []}) async {
    lastArgs = args;
    lastExePath = exePath;
    return null;
  }

  @override
  Future<void> launchStandalone(String emulatorId, String exePath,
      {List<String> args = const []}) async {}
}

Game _makeGame(String name, String slug) {
  return Game(id: '1', name: name, fileSize: 0, platformSlug: slug);
}

void main() {
  group('AresStrategy', () {
    test('emulatorId is ares', () {
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

  group('getSystemNameForSlug', () {
    late AresStrategy strategy;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      strategy = AresStrategy(_MockDirectoryService(prefs), platform: PlatformInfo('linux'));
    });

    test('returns correct name for known slug', () {
      expect(strategy.getSystemNameForSlug('gba'), 'Game Boy Advance');
      expect(strategy.getSystemNameForSlug('snes'), 'Super Famicom');
      expect(strategy.getSystemNameForSlug('n64'), 'Nintendo 64');
      expect(strategy.getSystemNameForSlug('genesis'), 'Mega Drive');
      expect(strategy.getSystemNameForSlug('psx'), 'PlayStation');
    });

    test('is case-insensitive', () {
      expect(strategy.getSystemNameForSlug('GBA'), 'Game Boy Advance');
      expect(strategy.getSystemNameForSlug('Gba'), 'Game Boy Advance');
    });

    test('returns null for unknown slug', () {
      expect(strategy.getSystemNameForSlug('ps5'), isNull);
      expect(strategy.getSystemNameForSlug('switch'), isNull);
    });

    test('returns null for null input', () {
      expect(strategy.getSystemNameForSlug(null), isNull);
    });
  });

  group('supportedSlugs', () {
    test('includes all kAresSystemNames keys', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final strategy = AresStrategy(_MockDirectoryService(prefs), platform: PlatformInfo('linux'));
      expect(strategy.supportedSlugs, containsAll(kAresSystemNames.keys));
      expect(strategy.supportedSlugs.length, kAresSystemNames.length);
    });
  });

  group('launch args regression — no --fullscreen or --no-file-prompt', () {
    late AresStrategy strategy;
    late _MockDirectoryService mockDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      mockDir = _MockDirectoryService(prefs);
      strategy = AresStrategy(mockDir, platform: PlatformInfo('linux'));
    });

    test('launch passes only --system flag, no extra args', () async {
      final game = _makeGame('Test.gba', 'gba');
      await strategy.launch(game, '/roms/test.gba');

      expect(mockDir.lastArgs, ['--system', 'Game Boy Advance']);
      expect(mockDir.lastArgs, isNot(contains('--fullscreen')),
          reason: 'Ares does not support --fullscreen');
      expect(mockDir.lastArgs, isNot(contains('--no-file-prompt')),
          reason: 'Ares does not support --no-file-prompt');
    });

    test('launchWithHandle passes only --system flag', () async {
      final game = _makeGame('Test.n64', 'n64');
      await strategy.launchWithHandle(game, '/roms/test.n64');

      expect(mockDir.lastArgs, ['--system', 'Nintendo 64']);
      expect(mockDir.lastArgs, isNot(contains('--fullscreen')));
      expect(mockDir.lastArgs, isNot(contains('--no-file-prompt')));
    });

    test('launch uses correct exe path', () async {
      final game = _makeGame('Test.gba', 'gba');
      await strategy.launch(game, '/roms/test.gba');

      expect(mockDir.lastExePath, '/fake/ares');
    });
  });

  group('unsupported platform throws', () {
    test('launch throws for unknown platform slug', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final strategy = AresStrategy(_MockDirectoryService(prefs), platform: PlatformInfo('linux'));
      final game = _makeGame('Game.ps5', 'ps5');

      expect(
        () => strategy.launch(game, '/roms/game.ps5'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('does not support platform'),
        )),
      );
    });

    test('launchWithHandle throws for unknown platform slug', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final strategy = AresStrategy(_MockDirectoryService(prefs), platform: PlatformInfo('linux'));
      final game = _makeGame('Game.switch', 'switch');

      expect(
        () => strategy.launchWithHandle(game, '/roms/game.switch'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('does not support platform'),
        )),
      );
    });
  });
}
