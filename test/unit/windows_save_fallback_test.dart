import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/windows_save_strategy.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('save-like names: save extensions, "save" and "eeprom", not game data', () {
    for (final yes in ['a/slot1.sav', 'a/Game.SRM', 'a/eeprom.bin', 'a/save01.dat', 'a/MySaveGame.bin', 'a/c.mpk']) {
      expect(WindowsSaveStrategy.looksLikeSaveFile(yes), isTrue, reason: yes);
    }
    for (final no in ['a/game.exe', 'a/data.pak', 'a/textures.bin', 'a/music.ogg', 'a/README.txt', 'a/config.ini']) {
      expect(WindowsSaveStrategy.looksLikeSaveFile(no), isFalse, reason: no);
    }
  });

  group('game folder standing in for the save folder', () {
    late Directory game;
    late WindowsSaveStrategy strategy;
    final g = Game(id: 'fallback1', name: 'Some Game', fileSize: 0, platformSlug: 'windows');

    setUp(() async {
      game = await Directory.systemTemp.createTemp('win_fallback_');
      SharedPreferences.setMockInitialValues({});
      strategy = WindowsSaveStrategy(SharedPreferencesAppPreferences(await SharedPreferences.getInstance()));
    });
    tearDown(() => game.delete(recursive: true));

    test('a game with only its own data has no saves (it is not backed up or uploaded)', () async {
      File(p.join(game.path, 'Game.exe')).writeAsStringSync('exe');
      File(p.join(game.path, 'data.pak')).writeAsStringSync('x' * 5000);
      expect(await strategy.getSaveFiles(g, game.path), isEmpty);
    });

    test('only the save-like files are returned, not the whole folder', () async {
      File(p.join(game.path, 'Game.exe')).writeAsStringSync('exe');
      File(p.join(game.path, 'data.pak')).writeAsStringSync('x' * 5000);
      File(p.join(game.path, 'eeprom.bin')).writeAsStringSync('save data');
      Directory(p.join(game.path, 'profiles')).createSync();
      File(p.join(game.path, 'profiles', 'slot1.sav')).writeAsStringSync('slot');
      final files = await strategy.getSaveFiles(g, game.path);
      expect(files.map((f) => p.basename(f.path)).toList()..sort(), ['eeprom.bin', 'slot1.sav']);
    });
  });
}
