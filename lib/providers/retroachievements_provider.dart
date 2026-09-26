import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freegosy/core/retroachievements/retroachievements_game_models.dart';
import 'package:freegosy/core/retroachievements/retroachievements_models.dart';
import 'package:freegosy/core/retroachievements/retroachievements_service.dart';
import 'package:freegosy/core/storage/secure_storage_service.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';

const _usernameKey = 'retroAchievementsUsername';
const _webApiKeySecureKey = 'retroAchievementsWebApiKey';

/// Loads the persisted RetroAchievements credentials, if any were saved via
/// the Settings screen. The Web API key is stored through
/// [SecureStorageService] (keychain/DPAPI/libsecret, with a SharedPreferences
/// fallback), matching how the RomM API key is stored.
final retroAchievementsCredentialsProvider = FutureProvider<RetroAchievementsCredentials?>((ref) async {
  final prefs = ref.watch(appPreferencesProvider);
  final username = prefs.getString(_usernameKey) ?? '';
  final webApiKey = await SecureStorageService.read(_webApiKeySecureKey, prefs) ?? '';
  final credentials = RetroAchievementsCredentials(username: username, webApiKey: webApiKey);
  return credentials.isEmpty ? null : credentials;
});

final retroAchievementsServiceProvider = Provider<RetroAchievementsService>((ref) {
  return RetroAchievementsService();
});

/// Fetches the connected user's profile. Empty (no saved credentials)
/// resolves to null rather than hitting the network.
final retroAchievementsProfileProvider = FutureProvider<RetroAchievementsProfile?>((ref) async {
  final credentials = await ref.watch(retroAchievementsCredentialsProvider.future);
  if (credentials == null) return null;
  final service = ref.watch(retroAchievementsServiceProvider);
  return service.fetchProfile(credentials);
});

/// Fetches the connected user's progress through one RetroAchievements game,
/// keyed by RA game ID (RomM's `ra_id`). Resolves to null when no account is
/// connected. Auto-disposed so reopening a game shows fresh unlocks.
final retroAchievementsGameProgressProvider =
    FutureProvider.autoDispose.family<RetroAchievementsGameProgress?, int>((ref, gameId) async {
  final credentials = await ref.watch(retroAchievementsCredentialsProvider.future);
  if (credentials == null) return null;
  final service = ref.watch(retroAchievementsServiceProvider);
  return service.fetchGameProgress(credentials, gameId);
});

/// Saves credentials and refreshes dependent providers. Throws
/// [RetroAchievementsAuthException] (surfaced by the caller's UI) if the
/// credentials are rejected — nothing is persisted in that case.
final retroAchievementsConnectProvider = Provider<Future<void> Function(RetroAchievementsCredentials)>((ref) {
  return (credentials) async {
    final service = ref.read(retroAchievementsServiceProvider);
    // Validate before persisting so a typo'd key doesn't get saved silently.
    await service.fetchProfile(credentials);

    final prefs = ref.read(appPreferencesProvider);
    await prefs.setString(_usernameKey, credentials.username);
    await SecureStorageService.write(_webApiKeySecureKey, credentials.webApiKey, prefs);

    ref.invalidate(retroAchievementsCredentialsProvider);
    ref.invalidate(retroAchievementsProfileProvider);
  };
});

final retroAchievementsDisconnectProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final prefs = ref.read(appPreferencesProvider);
    await prefs.remove(_usernameKey);
    await SecureStorageService.delete(_webApiKeySecureKey, prefs);

    ref.invalidate(retroAchievementsCredentialsProvider);
    ref.invalidate(retroAchievementsProfileProvider);
  };
});
