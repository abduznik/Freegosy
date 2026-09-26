import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import 'retroachievements_game_models.dart';
import 'retroachievements_models.dart';

/// Thin HTTP client for the read-only parts of the RetroAchievements Web API
/// (https://api-docs.retroachievements.org/) that Freegosy needs: verifying
/// a username/API-key pair, fetching that user's profile summary, and
/// fetching their progress through a single game.
///
/// This deliberately does NOT attempt to award/unlock achievements during
/// play — that requires the rcheevos client library watching live emulator
/// memory from inside the emulator process, which Freegosy (an external
/// launcher) has no access to. Emulators like RetroArch, Dolphin, and
/// PCSX2 already have their own built-in RetroAchievements support for
/// that; Freegosy's role here is limited to showing profile/progress data.
class RetroAchievementsService {
  static const String _baseUrl = 'https://retroachievements.org/API';
  static const String _connectUrl = 'https://retroachievements.org/dorequest.php';

  final Dio _dio;

  RetroAchievementsService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                // RA asks Connect API clients for "{Name}/{version} ({platform})".
                'User-Agent': 'Freegosy/${AppConstants.version} (${defaultTargetPlatform.name})',
                'Accept': 'application/json',
              },
            ));

  /// Fetches the profile summary for [credentials.username], also
  /// validating that the API key is correct.
  ///
  /// Throws [RetroAchievementsAuthException] if the credentials are
  /// rejected or the username doesn't exist. Other network/server errors
  /// propagate as [DioException].
  Future<RetroAchievementsProfile> fetchProfile(RetroAchievementsCredentials credentials) async {
    if (credentials.isEmpty) {
      throw const RetroAchievementsAuthException('Username and Web API key are required.');
    }

    try {
      final response = await _dio.get('/API_GetUserSummary.php', queryParameters: {
        'u': credentials.username,
        'y': credentials.webApiKey,
        'g': 0,
        'a': 0,
      });

      final data = response.data;
      if (data is! Map<String, dynamic> || data.isEmpty) {
        throw const RetroAchievementsAuthException('Invalid username or Web API key.');
      }
      // RA returns HTTP 200 with an empty/null-ish body for bad credentials
      // rather than a 401, so an empty payload is our real signal of failure.
      if (data['User'] == null && data['Username'] == null) {
        throw const RetroAchievementsAuthException('Invalid username or Web API key.');
      }

      return RetroAchievementsProfile.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw const RetroAchievementsAuthException('Invalid username or Web API key.');
      }
      debugPrint('[RetroAchievements] fetchProfile network error: $e');
      rethrow;
    }
  }

  /// Fetches [gameId]'s achievement set along with the connected user's
  /// unlock dates (API_GetGameInfoAndUserProgress.php).
  ///
  /// [gameId] is the RetroAchievements game ID, which RomM exposes as a
  /// ROM's `ra_id`. Throws [RetroAchievementsAuthException] on rejected
  /// credentials; other failures propagate as [DioException].
  Future<RetroAchievementsGameProgress> fetchGameProgress(
    RetroAchievementsCredentials credentials,
    int gameId,
  ) async {
    if (credentials.isEmpty) {
      throw const RetroAchievementsAuthException('Username and Web API key are required.');
    }

    try {
      final response = await _dio.get('/API_GetGameInfoAndUserProgress.php', queryParameters: {
        'u': credentials.username,
        'y': credentials.webApiKey,
        'g': gameId,
      });

      final data = response.data;
      if (data is! Map<String, dynamic> || data.isEmpty) {
        throw const RetroAchievementsAuthException('Invalid username or Web API key.');
      }
      return RetroAchievementsGameProgress.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw const RetroAchievementsAuthException('Invalid username or Web API key.');
      }
      debugPrint('[RetroAchievements] fetchGameProgress($gameId) network error: $e');
      rethrow;
    }
  }

  /// Exchanges the user's RA password for a Connect API token — the same
  /// token emulators obtain when you log in inside them — so Freegosy can
  /// sign emulators in on the user's behalf. The password is sent once, in
  /// the POST body (never the URL), and is not stored.
  ///
  /// Returns the token and the canonical username RA reports. Throws
  /// [RetroAchievementsAuthException] for a wrong username/password.
  Future<({String username, String token})> fetchConnectToken(String username, String password) async {
    if (username.isEmpty || password.isEmpty) {
      throw const RetroAchievementsAuthException('Username and password are required.');
    }

    try {
      final response = await _dio.post(
        _connectUrl,
        data: {'r': 'login2', 'u': username, 'p': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = response.data;
      final token = data is Map ? data['Token']?.toString() ?? '' : '';
      if (data is! Map || data['Success'] != true || token.isEmpty) {
        throw RetroAchievementsAuthException(
          (data is Map ? data['Error']?.toString() : null) ?? 'Invalid username or password.',
        );
      }
      return (username: data['User']?.toString() ?? username, token: token);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        final body = e.response?.data;
        throw RetroAchievementsAuthException(
          (body is Map ? body['Error']?.toString() : null) ?? 'Invalid username or password.',
        );
      }
      // Deliberately not logging `e`: its request options include the password.
      debugPrint('[RetroAchievements] fetchConnectToken network error (status $status)');
      rethrow;
    }
  }
}
