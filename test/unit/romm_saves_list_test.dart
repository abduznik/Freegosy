import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// A save list that couldn't be read must not look like "no saves".
void main() {
  const baseUrl = 'https://romm.example.com';
  late RommService service;
  late DioAdapter adapter;

  setUp(() {
    final dio = Dio(BaseOptions(baseUrl: baseUrl));
    adapter = DioAdapter(dio: dio);
    service = RommService(
      RomMConfig(baseUrl: baseUrl, username: '', password: '', apiKey: 'key'),
      dio: dio,
      skipConnectivityCheck: true,
    );
  });

  test('a listed game gives its saves, newest first', () async {
    adapter.onGet('/api/saves', (server) => server.reply(200, {
          'items': [
            {'id': 1, 'file_name': 'old.srm', 'updated_at': '2026-09-01T00:00:00Z'},
            {'id': 2, 'file_name': 'new.srm', 'updated_at': '2026-10-01T00:00:00Z'},
          ]
        }), queryParameters: {'rom_id': '7'});

    final saves = await service.getSavesListOrNull('7');

    expect(saves!.map((s) => s['file_name']), ['new.srm', 'old.srm']);
  });

  test('a game without saves gives an empty list', () async {
    adapter.onGet('/api/saves', (server) => server.reply(200, {'items': []}), queryParameters: {'rom_id': '7'});
    expect(await service.getSavesListOrNull('7'), isEmpty);
  });

  test('a server error gives null, not an empty list', () async {
    adapter.onGet('/api/saves', (server) => server.reply(500, {'detail': 'boom'}), queryParameters: {'rom_id': '7'});
    expect(await service.getSavesListOrNull('7'), isNull);
  });

  test('a refused request gives null', () async {
    adapter.onGet('/api/saves', (server) => server.reply(401, {'detail': 'no'}), queryParameters: {'rom_id': '7'});
    expect(await service.getSavesListOrNull('7'), isNull);
  });
}
