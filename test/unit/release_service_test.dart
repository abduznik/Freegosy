import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:freegosy/core/emulator/release_service.dart';

import 'release_service_test.mocks.dart';

@GenerateMocks([Dio])
void main() {
  late ReleaseService service;
  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    service = ReleaseService(mockDio);
  });

  group('Issue #63 — HTTP status code tolerance', () {
    test('getLatestReleaseAssets returns [] for non-2xx status codes', () async {
      when(mockDio.get(
        any,
        options: anyNamed('options'),
      )).thenAnswer((_) async => Response(
        data: {},
        statusCode: 403,
        requestOptions: RequestOptions(path: ''),
      ));

      final result = await service.getLatestReleaseAssets(
        platform: ReleasePlatform.github,
        repo: 'test/repo',
      );

      expect(result, isEmpty);
    });

    test('getLatestReleaseAssets returns assets for 200 status', () async {
      when(mockDio.get(
        any,
        options: anyNamed('options'),
      )).thenAnswer((_) async => Response(
        data: {
          'assets': [
            {
              'name': 'test.zip',
              'browser_download_url': 'https://example.com/test.zip',
            }
          ]
        },
        statusCode: 200,
        requestOptions: RequestOptions(path: ''),
      ));

      final result = await service.getLatestReleaseAssets(
        platform: ReleasePlatform.github,
        repo: 'test/repo',
      );

      expect(result.length, 1);
      expect(result[0]['name'], 'test.zip');
    });

    test('getLatestReleaseAssets returns [] for 429 rate limit', () async {
      when(mockDio.get(
        any,
        options: anyNamed('options'),
      )).thenAnswer((_) async => Response(
        data: {},
        statusCode: 429,
        requestOptions: RequestOptions(path: ''),
      ));

      final result = await service.getLatestReleaseAssets(
        platform: ReleasePlatform.github,
        repo: 'test/repo',
      );

      expect(result, isEmpty);
    });
  });
}
