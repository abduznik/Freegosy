import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freegosy/core/retroachievements/retroachievements_emulator_login.dart';
import 'package:freegosy/core/retroachievements/retroachievements_game_models.dart';
import 'package:freegosy/core/retroachievements/retroachievements_models.dart';
import 'package:freegosy/core/retroachievements/retroachievements_service.dart';
import 'package:freegosy/core/storage/secure_storage_service.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';

/// Loads the persisted RetroAchievements credentials, if any were saved via
/// the Settings screen. Only the username is required; `webApiKey` is empty
/// when the user skipped it. The Web API key is stored through
/// [SecureStorageService] (keychain/DPAPI/libsecret, with a SharedPreferences
/// fallback), matching how the RomM API key is stored.
final retroAchievementsCredentialsProvider = FutureProvider<RetroAchievementsCredentials?>((ref) async {
  final prefs = ref.watch(appPreferencesProvider);
  final username = prefs.getString(kRaUsernameKey) ?? '';
  final webApiKey = await SecureStorageService.read(kRaWebApiKeySecureKey, prefs) ?? '';
  final credentials = RetroAchievementsCredentials(username: username, webApiKey: webApiKey);
  return credentials.username.isEmpty ? null : credentials;
});

final retroAchievementsServiceProvider = Provider<RetroAchievementsService>((ref) {
  return RetroAchievementsService();
});

/// Fetches the connected user's profile. Empty (no saved credentials)
/// resolves to null rather than hitting the network.
final retroAchievementsProfileProvider = FutureProvider<RetroAchievementsProfile?>((ref) async {
  final credentials = await ref.watch(retroAchievementsCredentialsProvider.future);
  if (credentials == null || !credentials.hasWebApiKey) return null;
  final service = ref.watch(retroAchievementsServiceProvider);
  return service.fetchProfile(credentials);
});

/// Fetches the connected user's progress through one RetroAchievements game,
/// keyed by RA game ID (RomM's `ra_id`). Resolves to null when no account is
/// connected or no Web API key was given. Auto-disposed so reopening a game
/// shows fresh unlocks.
final retroAchievementsGameProgressProvider =
    FutureProvider.autoDispose.family<RetroAchievementsGameProgress?, int>((ref, gameId) async {
  final credentials = await ref.watch(retroAchievementsCredentialsProvider.future);
  if (credentials == null || !credentials.hasWebApiKey) return null;
  final service = ref.watch(retroAchievementsServiceProvider);
  return service.fetchGameProgress(credentials, gameId);
});

/// The user's RA progress as synced by RomM, keyed by RA game ID. Used when
/// no Web API key is set; empty when RomM has no RA data for the user.
final rommRetroAchievementsProgressionProvider = FutureProvider.autoDispose<Map<int, Map<String, dynamic>>>((ref) async {
  final romm = ref.watch(rommServiceProvider);
  if (romm == null) return {};
  return romm.getRetroAchievementsProgression();
});

/// Whether the RomM server has RetroAchievements enabled and which RA
/// username the user's RomM profile is linked to.
final rommRetroAchievementsStatusProvider = FutureProvider<RommRetroAchievementsStatus>((ref) async {
  final romm = ref.watch(rommServiceProvider);
  if (romm == null) return const RommRetroAchievementsStatus();
  final caps = await ref.watch(rommCapabilitiesProvider.future);
  if (caps.retroAchievementsEnabled != true) {
    return RommRetroAchievementsStatus(serverEnabled: caps.retroAchievementsEnabled);
  }
  final link = await romm.getRetroAchievementsLink();
  return RommRetroAchievementsStatus(serverEnabled: true, rommUserId: link?.id, linkedUsername: link?.raUsername);
});

/// Links [username] on the user's RomM profile and asks RomM to sync their
/// progress. Returns whether the sync succeeded (the link itself throws on
/// failure). Only call after the user agreed — it edits their RomM profile.
final linkRommRetroAchievementsProvider = Provider<Future<bool> Function(String username)>((ref) {
  return (username) async {
    final romm = ref.read(rommServiceProvider);
    final status = await ref.read(rommRetroAchievementsStatusProvider.future);
    final userId = status.rommUserId;
    if (romm == null || userId == null) {
      throw StateError('Could not reach your RomM profile.');
    }
    await romm.setRetroAchievementsUsername(userId, username);
    final synced = await romm.refreshRetroAchievements(userId);
    ref.invalidate(rommRetroAchievementsStatusProvider);
    ref.invalidate(rommRetroAchievementsProgressionProvider);
    return synced;
  };
});

/// The username/token emulators are signed in with, or null when the account
/// was connected without a password (profile/progress only).
final retroAchievementsEmulatorLoginProvider = FutureProvider<RetroAchievementsEmulatorLogin?>((ref) {
  return RetroAchievementsEmulatorLogin.load(ref.watch(appPreferencesProvider));
});

void _invalidateAll(Ref ref) {
  ref.invalidate(retroAchievementsCredentialsProvider);
  ref.invalidate(retroAchievementsProfileProvider);
  ref.invalidate(retroAchievementsEmulatorLoginProvider);
}

/// Saves credentials and refreshes dependent providers. Throws
/// [RetroAchievementsAuthException] (surfaced by the caller's UI) if the Web
/// API key or the optional [password] is rejected — nothing is persisted in
/// that case.
///
/// With a [password], RA is asked for an emulator login token, which is
/// stored instead of the password. Without one, an existing token is kept
/// only if the username is unchanged, so emulators are never signed in to a
/// different account than the one shown in Settings.
final retroAchievementsConnectProvider =
    Provider<Future<void> Function(RetroAchievementsCredentials, {String? password})>((ref) {
  return (credentials, {password}) async {
    final service = ref.read(retroAchievementsServiceProvider);
    final hasPassword = password != null && password.isNotEmpty;
    if (credentials.username.isEmpty) {
      throw const RetroAchievementsAuthException('Username is required.');
    }
    if (!hasPassword && !credentials.hasWebApiKey) {
      throw const RetroAchievementsAuthException('Enter your password, your Web API key, or both.');
    }
    // Validate before persisting so a typo'd key doesn't get saved silently.
    if (credentials.hasWebApiKey) await service.fetchProfile(credentials);

    String? token;
    if (hasPassword) {
      final login = await service.fetchConnectToken(credentials.username, password);
      if (login.username.toLowerCase() != credentials.username.toLowerCase()) {
        throw const RetroAchievementsAuthException('That password belongs to a different RetroAchievements account.');
      }
      token = login.token;
    }

    final prefs = ref.read(appPreferencesProvider);
    final previousUsername = prefs.getString(kRaUsernameKey) ?? '';
    await prefs.setString(kRaUsernameKey, credentials.username);
    if (credentials.hasWebApiKey) {
      await SecureStorageService.write(kRaWebApiKeySecureKey, credentials.webApiKey, prefs);
    } else {
      await SecureStorageService.delete(kRaWebApiKeySecureKey, prefs);
    }
    if (token != null) {
      await SecureStorageService.write(kRaConnectTokenSecureKey, token, prefs);
    } else if (previousUsername.toLowerCase() != credentials.username.toLowerCase()) {
      await SecureStorageService.delete(kRaConnectTokenSecureKey, prefs);
    }

    _invalidateAll(ref);
  };
});

final retroAchievementsDisconnectProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final prefs = ref.read(appPreferencesProvider);
    await prefs.remove(kRaUsernameKey);
    await prefs.remove(kRaHardcoreKey);
    await SecureStorageService.delete(kRaWebApiKeySecureKey, prefs);
    await SecureStorageService.delete(kRaConnectTokenSecureKey, prefs);
    _invalidateAll(ref);
  };
});

final retroAchievementsSetHardcoreProvider = Provider<Future<void> Function(bool)>((ref) {
  return (enabled) async {
    await ref.read(appPreferencesProvider).setBool(kRaHardcoreKey, enabled);
    ref.invalidate(retroAchievementsEmulatorLoginProvider);
  };
});
