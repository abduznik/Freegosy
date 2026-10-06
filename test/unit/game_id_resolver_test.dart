import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/game_id_resolver.dart';
import 'package:freegosy/core/romm/romm_models.dart';

void main() {
  group('GameIdResolver', () {
    test('RomM\'s value wins and the ROM is never read', () async {
      var reads = 0;
      final id = await GameIdResolver.resolve(
          label: 'test',
          server: 'SLUS-20675',
          local: () async {
            reads++;
            return 'SLUS-99999';
          });
      expect(id, 'SLUS-20675');
      expect(reads, 0);
    });

    test('without a RomM value the ROM is read', () async {
      for (final server in [null, '', '   ']) {
        var reads = 0;
        final id = await GameIdResolver.resolve(
            label: 'test',
            server: server,
            local: () async {
              reads++;
              return 'SLUS-99999';
            });
        expect(id, 'SLUS-99999', reason: '"$server"');
        expect(reads, 1);
      }
    });

    test('values are trimmed; blank local answers count as none', () async {
      expect(await GameIdResolver.resolve(label: 't', server: ' SLUS-20675 ', local: () async => null), 'SLUS-20675');
      expect(await GameIdResolver.resolve(label: 't', local: () async => '  '), isNull);
    });

    test('server() cleans the value and gives null for nothing', () {
      expect(GameIdResolver.server('t', ' 0100ABCD12345000 '), '0100ABCD12345000');
      expect(GameIdResolver.server('t', ''), isNull);
      expect(GameIdResolver.server('t', null), isNull);
      expect(GameIdResolver.clean('\t'), isNull);
    });
  });

  group('GameIdResolver shape checks', () {
    final serial = RegExp(r'^[A-Z]{4}-\d{5}$');

    test('a RomM value that doesn\'t look like the id is ignored', () async {
      var reads = 0;
      final id = await GameIdResolver.resolve(
          label: 't',
          server: '../../x',
          shape: serial,
          local: () async {
            reads++;
            return 'SLUS-21050';
          });
      expect(id, 'SLUS-21050');
      expect(reads, 1);
      expect(GameIdResolver.server('t', '../../x', shape: serial), isNull);
    });

    test('a RomM value with the right shape is used', () {
      expect(GameIdResolver.server('t', 'SLUS-21050', shape: serial), 'SLUS-21050');
    });
  });

  group('GameIdResolver.isLaterDisc by the launched file name', () {
    final game = Game(id: 'd', name: 'Some Game', platformSlug: 'psx', fileSize: 0);
    for (final (name, later) in [
      ('Final Fantasy VII (USA) (Disc 2).chd', true),
      ('Game (Disc 2 of 3).chd', true),
      ('Game [CD 2].iso', true),
      ('Game (Disc 10).chd', true),
      ('Game - Disc 2.chd', true),
      ('Game (USA) (Disc 1).chd', false),
      ('Game (Disc 1-3).m3u', false),
      ('Discworld (USA).chd', false),
      ('Disco Elysium (CD-ROM).iso', false),
      ('Game (Disk Version).cue', false),
    ]) {
      test(name, () => expect(GameIdResolver.isLaterDisc(game, name), later));
    }
  });
}
