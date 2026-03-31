import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';

void main() {
  group('RomM Models', () {
    test('Platform.fromJson parses rom_count', () {
      final json = {
        'id': 1,
        'name': 'GBA',
        'slug': 'gba',
        'rom_count': 10,
      };
      final platform = Platform.fromJson(json);
      expect(platform.gamesCount, 10);
    });

    test('Platform.fromJson parses roms_count', () {
      final json = {
        'id': 1,
        'name': 'GBA',
        'slug': 'gba',
        'roms_count': 20,
      };
      final platform = Platform.fromJson(json);
      expect(platform.gamesCount, 20);
    });

    test('Platform.fromJson parses games_count', () {
      final json = {
        'id': 1,
        'name': 'GBA',
        'slug': 'gba',
        'games_count': 30,
      };
      final platform = Platform.fromJson(json);
      expect(platform.gamesCount, 30);
    });

    test('Platform.fromJson defaults games_count to 0', () {
      final json = {
        'id': 1,
        'name': 'GBA',
        'slug': 'gba',
      };
      final platform = Platform.fromJson(json);
      expect(platform.gamesCount, 0);
    });

    test('Game.fromJson parses all fields', () {
      final json = {
        'id': '123',
        'name': 'Game Name',
        'platform_id': 1,
        'platform_slug': 'gba',
        'platform_display_name': 'Game Boy Advance',
        'path_cover_large': '/large.jpg',
        'path_cover_small': '/small.jpg',
        'url_cover': 'https://example.com/cover.jpg',
        'url_download': 'https://example.com/download',
        'file_name': 'game.zip',
        'fs_name': 'game.zip',
        'file_size_bytes': 1024,
        'multi_file_path': null,
        'has_multiple_files': false,
      };
      final game = Game.fromJson(json);
      expect(game.id, '123');
      expect(game.name, 'Game Name');
      expect(game.fileSize, 1024);
      expect(game.fileName, 'game.zip');
    });

    test('Game.displayName cleans title correctly', () {
      final g1 = Game(id: '1', name: '00040000000EC400 Mario Kart 7 (USA) (En,Fr,Es)', fileSize: 0);
      expect(g1.displayName, 'Mario Kart 7');

      final g2 = Game(id: '2', name: 'Crash Bandicoot [!] [b]', fileSize: 0);
      expect(g2.displayName, 'Crash Bandicoot');

      final g3 = Game(id: '3', name: 'Game_Title_ (v1.0) .', fileSize: 0);
      expect(g3.displayName, 'Game_Title');
    });

    test('SaveFile.fromJson parses all fields', () {
      final json = {
        'id': '456',
        'game_id': '123',
        'url': 'https://example.com/save',
      };
      final save = SaveFile.fromJson(json);
      expect(save.id, '456');
      expect(save.gameId, '123');
      expect(save.url, 'https://example.com/save');
    });
  });
}
