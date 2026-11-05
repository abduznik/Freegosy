import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';

/// #202: a manual RomM holds is opened from the server, not downloaded.
void main() {
  Game game(Map<String, dynamic> extra) => Game.fromJson({'id': 1, 'name': 'G', ...extra});

  test('a manual on the RomM server is linked through the server address', () {
    final g = game({'path_manual': '/assets/romm/resources/roms/1/2/manual/2.pdf'});
    expect(g.manualLink('http://romm.local:8080'), 'http://romm.local:8080/assets/romm/resources/roms/1/2/manual/2.pdf');
    expect(g.manualLink('http://romm.local:8080/'), 'http://romm.local:8080/assets/romm/resources/roms/1/2/manual/2.pdf');
  });

  test('without a stored manual the provider link is used', () {
    expect(game({'url_manual': 'https://example.com/m.pdf'}).manualLink('http://x'), 'https://example.com/m.pdf');
    expect(game({'url_manual': '//example.com/m.pdf'}).manualLink('http://x'), 'https://example.com/m.pdf');
  });

  test('a game without a manual has no link', () {
    expect(game({}).manualLink('http://x'), isNull);
    expect(game({'path_manual': '', 'url_manual': ''}).manualLink('http://x'), isNull);
  });

  test('the manual survives the library cache', () {
    final g = game({'path_manual': '/assets/m.pdf'});
    expect(Game.fromJson(g.toJson()).manualLink('http://x'), 'http://x/assets/m.pdf');
  });
}
