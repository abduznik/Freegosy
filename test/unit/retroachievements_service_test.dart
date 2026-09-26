import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:freegosy/core/retroachievements/retroachievements_game_models.dart';
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

  group('RetroAchievementsService.fetchGameProgress', () {
    const credentials = RetroAchievementsCredentials(username: testUsername, webApiKey: testApiKey);

    test('parses achievements, unlock dates and the highest award', () async {
      dioAdapter.onGet(
        '/API_GetGameInfoAndUserProgress.php',
        (server) => server.reply(200, {
          'ID': 1,
          'Title': 'Sonic the Hedgehog',
          'ConsoleName': 'Mega Drive',
          'ImageIcon': '/Images/067895.png',
          'HighestAwardKind': 'beaten-hardcore',
          'Achievements': {
            '10': {
              'ID': 10,
              'Title': 'Second',
              'Description': 'b',
              'Points': 5,
              'BadgeName': '222',
              'DisplayOrder': 2,
              'type': 'progression',
              'NumAwarded': 100,
              'NumAwardedHardcore': 40,
            },
            '9': {
              'ID': 9,
              'Title': 'First',
              'Description': 'a',
              'Points': 3,
              'BadgeName': '111',
              'DisplayOrder': 1,
              'type': null,
              'DateEarned': '2016-03-12 17:47:29',
              'DateEarnedHardcore': '2016-03-12 17:47:29',
            },
          },
        }),
        queryParameters: {'u': testUsername, 'y': testApiKey, 'g': 1},
      );

      final progress = await service.fetchGameProgress(credentials, 1);

      expect(progress.gameId, 1);
      expect(progress.iconUrl, 'https://media.retroachievements.org/Images/067895.png');
      expect(progress.highestAward, RetroAchievementsAward.beatenHardcore);
      expect(progress.achievements.map((a) => a.id), [9, 10]);
      expect(progress.unlockedCount, 1);
      expect(progress.unlockedHardcoreCount, 1);
      expect(progress.earnedPoints, 3);
      expect(progress.totalPoints, 8);

      final first = progress.achievements.first;
      expect(first.dateEarned, DateTime.utc(2016, 3, 12, 17, 47, 29));
      expect(first.type, isNull);
      expect(first.badgeUrl, 'https://media.retroachievements.org/Badge/111.png');
      expect(progress.achievements.last.lockedBadgeUrl, 'https://media.retroachievements.org/Badge/222_lock.png');
      expect(progress.achievements.last.isUnlocked, isFalse);
    });

    test('handles a game with no achievements (PHP empty array)', () async {
      dioAdapter.onGet(
        '/API_GetGameInfoAndUserProgress.php',
        (server) => server.reply(200, {'ID': 5, 'Title': 'Empty', 'Achievements': [], 'HighestAwardKind': null}),
        queryParameters: {'u': testUsername, 'y': testApiKey, 'g': 5},
      );

      final progress = await service.fetchGameProgress(credentials, 5);

      expect(progress.achievements, isEmpty);
      expect(progress.highestAward, isNull);
    });

    test('throws RetroAchievementsAuthException for a 401 response', () async {
      dioAdapter.onGet(
        '/API_GetGameInfoAndUserProgress.php',
        (server) => server.reply(401, {'error': 'Unauthorized'}),
        queryParameters: {'u': testUsername, 'y': testApiKey, 'g': 1},
      );

      expect(() => service.fetchGameProgress(credentials, 1), throwsA(isA<RetroAchievementsAuthException>()));
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
