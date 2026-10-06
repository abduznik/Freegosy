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

    test('Game.fromJson lowercases status', () {
      final json = {
        'id': '123',
        'name': 'Game Name',
        'file_size_bytes': 0,
        'rom_user': {
          'status': 'Playing',
        },
      };
      final game = Game.fromJson(json);
      expect(game.status, 'playing');
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
        'rom_id': '123',
        'download_path': 'https://example.com/save',
      };
      final save = SaveFile.fromJson(json);
      expect(save.id, '456');
      expect(save.romId, '123');
      expect(save.url, 'https://example.com/save');
    });

    test('RomNote.fromJson parses all fields', () {
      final json = {
        'id': 789,
        'title': 'Test Note',
        'content': 'This is a test note.',
        'created_at': '2023-01-01T12:00:00Z',
        'updated_at': '2023-01-02T12:00:00Z',
      };
      final note = RomNote.fromJson(json);
      expect(note.id, 789);
      expect(note.title, 'Test Note');
      expect(note.content, 'This is a test note.');
      expect(note.createdAt, DateTime.parse('2023-01-01T12:00:00Z'));
      expect(note.updatedAt, DateTime.parse('2023-01-02T12:00:00Z'));
    });

    test('Platform.nameForDisplay uses displayName when available', () {
      final p1 = Platform(id: 1, name: 'SFC', slug: 'sfc', displayName: 'Super Nintendo');
      expect(p1.nameForDisplay, 'Super Nintendo');

      final p2 = Platform(id: 2, name: 'GBA', slug: 'gba', displayName: '');
      expect(p2.nameForDisplay, 'GBA');
    });
  });

  group('Game: the id RomM read from the ROM (RomM 5.3+)', () {
    test('title_id, save_target and save_target_layout are read', () {
      final game = Game.fromJson({
        'id': 7,
        'name': 'Ico',
        'title_id': 'SCUS-97113',
        'save_target': 'BASCUS-97113',
        'save_target_layout': 'FOLDER_PREFIX',
      });
      expect(game.titleId, 'SCUS-97113');
      expect(game.saveTarget, 'BASCUS-97113');
      expect(game.saveTargetLayout, SaveTargetLayout.folderPrefix);
    });

    test('an older server sends none of them', () {
      final game = Game.fromJson({'id': 7, 'name': 'Ico'});
      expect(game.titleId, isNull);
      expect(game.saveTarget, isNull);
      expect(game.saveTargetLayout, isNull);
    });

    test('an unknown layout or a non-string value is null, not an error', () {
      final game = Game.fromJson({'id': 7, 'name': 'Ico', 'save_target_layout': 'SIDEWAYS', 'title_id': 12});
      expect(game.saveTargetLayout, isNull);
      expect(game.titleId, isNull);
      expect(SaveTargetLayout.fromJson(42), isNull);
    });

    test('the layout as the RomM API really sends it (lower case, hyphens)', () {
      expect(Game.fromJson({'id': 1, 'name': 'Burnout 3', 'save_target_layout': 'folder-prefix'}).saveTargetLayout,
          SaveTargetLayout.folderPrefix);
      expect({
        for (final v in ['folder-exact', 'folder-prefix', 'file-exact', 'file-prefix', 'folder-split'])
          SaveTargetLayout.fromJson(v)
      }, SaveTargetLayout.values.toSet());
    });

    test('every layout RomM sends is known', () {
      expect({
        for (final v in ['FOLDER_EXACT', 'FOLDER_PREFIX', 'FILE_EXACT', 'FILE_PREFIX', 'FOLDER_SPLIT'])
          SaveTargetLayout.fromJson(v)
      }, SaveTargetLayout.values.toSet());
    });

    test('toJson keeps them, so a cached game still has its id', () {
      final game = Game.fromJson({
        'id': 7,
        'name': 'Pilotwings',
        'title_id': '0004000000033500',
        'save_target': '00040000/00033500',
        'save_target_layout': 'FOLDER_SPLIT',
      });
      final again = Game.fromJson(game.toJson());
      expect(again.titleId, '0004000000033500');
      expect(again.saveTarget, '00040000/00033500');
      expect(again.saveTargetLayout, SaveTargetLayout.folderSplit);
    });
  });
}
