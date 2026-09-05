import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import 'retroachievements_models.dart';

/// Thin HTTP client for the read-only parts of the RetroAchievements Web API
/// (https://api-docs.retroachievements.org/) that Freegosy needs: verifying
/// a username/API-key pair and fetching that user's profile summary.
///
/// This deliberately does NOT attempt to award/unlock achievements during
/// play — that requires the rcheevos client library watching live emulator
/// memory from inside the emulator process, which Freegosy (an external
/// launcher) has no access to. Emulators like RetroArch, Dolphin, and
/// PCSX2 already have their own built-in RetroAchievements support for
/// that; Freegosy's role here is limited to showing profile/progress data.
class RetroAchievementsService {
  static const String _baseUrl = 'https://retroachievements.org/API';

  final Dio _dio;

  RetroAchievementsService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'User-Agent': 'Freegosy/${AppConstants.version}',
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
}
