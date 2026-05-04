import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';

void main() {
  late RommService rommService;
  late Dio dio;
  late DioAdapter dioAdapter;

  const String testBaseUrl = 'https://romm.example.com';
  const String testApiKey = 'test_api_key_12345';

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: testBaseUrl));
    dioAdapter = DioAdapter(dio: dio);
    
    final config = RomMConfig(
      baseUrl: testBaseUrl,
      username: '',
      password: '',
      apiKey: testApiKey,
    );
    
    rommService = RommService(config, dio: dio);
  });

  group('RommService API Authentication', () {
    test('sends API Key in both Authorization and X-Api-Key headers', () async {
      // Setup mock response
      dioAdapter.onGet(
        '/api/platforms',
        (server) => server.reply(200, {'items': []}),
        headers: {
          'Authorization': 'Bearer $testApiKey',
          'X-Api-Key': testApiKey,
        },
      );

      // Call the API
      final platforms = await rommService.getPlatforms();

      // Verify results
      expect(platforms, isEmpty);
    });

    test('getPlatforms correctly parses platforms list', () async {
      // Mock data
      final mockData = {
        'items': [
          {
            'id': 1,
            'name': 'Nintendo Switch',
            'slug': 'switch',
            'display_name': 'Switch',
            'rom_count': 10,
          },
          {
            'id': 2,
            'name': 'PlayStation 2',
            'slug': 'ps2',
            'display_name': 'PS2',
            'rom_count': 5,
          }
        ]
      };

      dioAdapter.onGet(
        '/api/platforms',
        (server) => server.reply(200, mockData),
      );

      final platforms = await rommService.getPlatforms();

      expect(platforms.length, 2);
      expect(platforms[0].id, 1);
      expect(platforms[0].name, 'Nintendo Switch');
      expect(platforms[1].slug, 'ps2');
    });

    test('getPlatforms throws DioException on error response', () async {
      dioAdapter.onGet(
        '/api/platforms',
        (server) => server.reply(401, {'message': 'Unauthorized'}),
      );

      expect(() => rommService.getPlatforms(), throwsA(isA<DioException>()));
    });
  });
}
