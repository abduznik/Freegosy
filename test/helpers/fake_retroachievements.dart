import 'package:dio/dio.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/retroachievements/retroachievements_game_models.dart';
import 'package:freegosy/core/retroachievements/retroachievements_models.dart';
import 'package:freegosy/core/retroachievements/retroachievements_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/storage/app_preferences.dart';
import 'package:freegosy/core/storage/secure_storage_service.dart';

/// In-memory [AppPreferences] for RetroAchievements tests.
class InMemoryAppPreferences implements AppPreferences {
  final Map<String, Object> values;
  InMemoryAppPreferences([Map<String, Object>? initial]) : values = {...?initial};

  @override
  String? getString(String key) => values[key] as String?;
  @override
  bool? getBool(String key) => values[key] as bool?;
  @override
  Set<String> getKeys() => values.keys.toSet();
  @override
  Future<bool> setString(String key, String value) async => (values[key] = value) == value;
  @override
  Future<bool> setBool(String key, bool value) async => (values[key] = value) == value;
  @override
  Future<bool> remove(String key) async => values.remove(key) != null;
}

/// Routes [SecureStorageService] through [AppPreferences] (its macOS path,
/// stored as `macos_secure_<key>`) so tests can observe secrets without the
/// platform keychain plugin. Call [resetSecureStorage] in tearDown.
void useInMemorySecureStorage() => SecureStorageService.configure(platform: const PlatformInfo('macos'));
void resetSecureStorage() => SecureStorageService.configure();

String secureKey(String key) => 'macos_secure_$key';

/// Scriptable stand-in for the RA HTTP client that records every call.
class FakeRetroAchievementsService extends RetroAchievementsService {
  final List<String> calls = [];

  /// Username RA reports back for a password login (canonical casing).
  String loginUsername;
  String token;
  Object? profileError;
  Object? loginError;
  RetroAchievementsGameProgress? progress;

  FakeRetroAchievementsService({this.loginUsername = 'Player', this.token = 'tok123', this.progress});

  @override
  Future<RetroAchievementsProfile> fetchProfile(RetroAchievementsCredentials credentials) async {
    calls.add('profile:${credentials.username}');
    if (profileError != null) throw profileError!;
    return RetroAchievementsProfile(
      username: credentials.username,
      rank: 1,
      totalPoints: 100,
      totalTruePoints: 200,
    );
  }

  @override
  Future<({String username, String token})> fetchConnectToken(String username, String password) async {
    calls.add('login:$username');
    if (loginError != null) throw loginError!;
    return (username: loginUsername, token: token);
  }

  @override
  Future<RetroAchievementsGameProgress> fetchGameProgress(RetroAchievementsCredentials credentials, int gameId) async {
    calls.add('progress:$gameId');
    return progress ?? RetroAchievementsGameProgress(gameId: gameId, title: '', consoleName: '', achievements: const []);
  }
}

/// RommService stand-in for the RetroAchievements link flow.
class FakeRommRaService extends RommService {
  final List<String> calls = [];
  bool? raEnabled;
  int? userId;
  String? linkedUsername;
  bool refreshSucceeds;
  Object? setError;

  FakeRommRaService({this.raEnabled = true, this.userId = 5, this.linkedUsername, this.refreshSucceeds = true})
      : super(
          RomMConfig(baseUrl: 'https://romm.test', username: '', password: '', apiKey: 'k'),
          dio: Dio(),
          skipConnectivityCheck: true,
        );

  @override
  Future<RommCapabilities> fetchCapabilities() async =>
      RommCapabilities(version: '4.9.0', retroAchievementsEnabled: raEnabled);

  @override
  Future<({int id, String? raUsername})?> getRetroAchievementsLink() async {
    calls.add('me');
    return userId == null ? null : (id: userId!, raUsername: linkedUsername);
  }

  @override
  Future<void> setRetroAchievementsUsername(int userId, String raUsername) async {
    calls.add('set:$userId:$raUsername');
    if (setError != null) throw setError!;
    linkedUsername = raUsername;
  }

  @override
  Future<bool> refreshRetroAchievements(int userId) async {
    calls.add('refresh:$userId');
    return refreshSucceeds;
  }

  @override
  Future<Map<int, Map<String, dynamic>>> getRetroAchievementsProgression() async => {};
}
