import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// RommService.getRetroAchievementsProgression reads the RA progress RomM
/// synced for the current user (`ra_progression` on /api/users/me).
void main() {
  const baseUrl = 'https://romm.test';
  late DioAdapter adapter;
  late RommService romm;

  setUp(() {
    final dio = Dio(BaseOptions(baseUrl: baseUrl));
    adapter = DioAdapter(dio: dio);
    romm = RommService(RomMConfig(baseUrl: baseUrl, username: '', password: '', apiKey: 'k'), dio: dio);
  });

  test('keys results by rom_ra_id', () async {
    adapter.onGet('/api/users/me', (s) => s.reply(200, {
          'username': 'me',
          'ra_username': 'Player',
          'ra_progression': {
            'total': 2,
            'results': [
              {'rom_ra_id': 1, 'num_awarded': 3, 'earned_achievements': []},
              {'rom_ra_id': 2, 'num_awarded': 0, 'earned_achievements': []},
              {'rom_ra_id': null, 'num_awarded': 0}, // unmatched: skipped
            ],
          },
        }));

    final progression = await romm.getRetroAchievementsProgression();

    expect(progression.keys, unorderedEquals([1, 2]));
    expect(progression[1]!['num_awarded'], 3);
  });

  test('is empty when the user has no RA progression', () async {
    adapter.onGet('/api/users/me', (s) => s.reply(200, {'username': 'me', 'ra_username': null, 'ra_progression': null}));
    expect(await romm.getRetroAchievementsProgression(), isEmpty);
  });

  test('is empty on older RomM servers without the field', () async {
    adapter.onGet('/api/users/me', (s) => s.reply(200, {'username': 'me'}));
    expect(await romm.getRetroAchievementsProgression(), isEmpty);
  });

  test('is empty (not an error) when the request fails', () async {
    adapter.onGet('/api/users/me', (s) => s.reply(500, {'detail': 'boom'}));
    expect(await romm.getRetroAchievementsProgression(), isEmpty);
  });
}
