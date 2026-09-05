import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:freegosy/core/retroachievements/retroachievements_models.dart';
import 'package:freegosy/core/retroachievements/retroachievements_service.dart';

void main() {
  late RetroAchievementsService service;
  late Dio dio;
  late DioAdapter dioAdapter;

  const testBaseUrl = 'https://retroachievements.org/API';
  const testUsername = 'testuser';
  const testApiKey = 'test_web_api_key';

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: testBaseUrl));
    dioAdapter = DioAdapter(dio: dio);
    service = RetroAchievementsService(dio: dio);
  });

  group('RetroAchievementsService.fetchProfile', () {
    test('parses a valid profile response', () async {
      dioAdapter.onGet(
        '/API_GetUserSummary.php',
        (server) => server.reply(200, {
          'User': testUsername,
          'Rank': '4616',
          'TotalPoints': '8317',
          'TotalTruePoints': '26760',
          'UserPic': '/UserPic/$testUsername.png',
          'MemberSince': '2015-03-01 12:00:00',
        }),
        queryParameters: {
          'u': testUsername,
          'y': testApiKey,
          'g': 0,
          'a': 0,
        },
      );

      final profile = await service.fetchProfile(
        const RetroAchievementsCredentials(username: testUsername, webApiKey: testApiKey),
      );

      expect(profile.username, testUsername);
      expect(profile.rank, 4616);
      expect(profile.totalPoints, 8317);
      expect(profile.totalTruePoints, 26760);
      expect(profile.avatarUrl, 'https://media.retroachievements.org/UserPic/$testUsername.png');
      expect(profile.memberSince, isNotNull);
    });

    test('throws RetroAchievementsAuthException for an empty/invalid-credentials response', () async {
      dioAdapter.onGet(
        '/API_GetUserSummary.php',
        (server) => server.reply(200, {}),
        queryParameters: {
          'u': testUsername,
          'y': 'wrong_key',
          'g': 0,
          'a': 0,
        },
      );

      expect(
        () => service.fetchProfile(
          const RetroAchievementsCredentials(username: testUsername, webApiKey: 'wrong_key'),
        ),
        throwsA(isA<RetroAchievementsAuthException>()),
      );
    });

    test('throws RetroAchievementsAuthException for a 401 response', () async {
      dioAdapter.onGet(
        '/API_GetUserSummary.php',
        (server) => server.reply(401, {'error': 'Unauthorized'}),
        queryParameters: {
          'u': testUsername,
          'y': testApiKey,
          'g': 0,
          'a': 0,
        },
      );

      expect(
        () => service.fetchProfile(
          const RetroAchievementsCredentials(username: testUsername, webApiKey: testApiKey),
        ),
        throwsA(isA<RetroAchievementsAuthException>()),
      );
    });

    test('throws RetroAchievementsAuthException without making a request when credentials are empty', () async {
      expect(
        () => service.fetchProfile(const RetroAchievementsCredentials(username: '', webApiKey: '')),
        throwsA(isA<RetroAchievementsAuthException>()),
      );
    });

    test('propagates non-auth network errors as DioException', () async {
      dioAdapter.onGet(
        '/API_GetUserSummary.php',
        (server) => server.reply(500, {'error': 'Internal Server Error'}),
        queryParameters: {
          'u': testUsername,
          'y': testApiKey,
          'g': 0,
          'a': 0,
        },
      );

      expect(
        () => service.fetchProfile(
          const RetroAchievementsCredentials(username: testUsername, webApiKey: testApiKey),
        ),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('RetroAchievementsCredentials', () {
    test('isEmpty is true when either field is blank', () {
      expect(const RetroAchievementsCredentials(username: '', webApiKey: 'x').isEmpty, isTrue);
      expect(const RetroAchievementsCredentials(username: 'x', webApiKey: '').isEmpty, isTrue);
      expect(const RetroAchievementsCredentials(username: 'x', webApiKey: 'y').isEmpty, isFalse);
    });
  });
}
