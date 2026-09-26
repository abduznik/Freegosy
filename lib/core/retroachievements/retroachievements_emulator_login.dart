import 'package:freegosy/core/storage/app_preferences.dart';
import 'package:freegosy/core/storage/secure_storage_service.dart';

/// Storage keys shared by the Settings flow (which writes them) and the
/// emulator strategies (which read them at launch).
const kRaUsernameKey = 'retroAchievementsUsername';
const kRaWebApiKeySecureKey = 'retroAchievementsWebApiKey';
const kRaConnectTokenSecureKey = 'retroAchievementsConnectToken';
const kRaHardcoreKey = 'retroAchievementsHardcore';

/// What an emulator needs to sign in to RetroAchievements: the username and
/// the Connect API token RA issued when the user gave Freegosy their password
/// once. The password itself is never stored.
class RetroAchievementsEmulatorLogin {
  final String username;
  final String token;
  final bool hardcore;

  const RetroAchievementsEmulatorLogin({required this.username, required this.token, this.hardcore = false});

  /// Null when no account is connected or it was connected without a
  /// password (Web-API-only), in which case emulators are left untouched.
  static Future<RetroAchievementsEmulatorLogin?> load(AppPreferences prefs) async {
    final username = prefs.getString(kRaUsernameKey) ?? '';
    // Checked first so launches without an RA account never touch the keychain.
    if (username.isEmpty) return null;
    final token = await SecureStorageService.read(kRaConnectTokenSecureKey, prefs) ?? '';
    if (token.isEmpty) return null;
    return RetroAchievementsEmulatorLogin(
      username: username,
      token: token,
      hardcore: prefs.getBool(kRaHardcoreKey) ?? false,
    );
  }

  /// RetroArch config overrides, passed via `--appendconfig` so the user's
  /// own retroarch.cfg is never edited by Freegosy.
  String toRetroArchConfig() {
    String quote(String v) => '"${v.replaceAll('"', '')}"';
    return [
      'cheevos_enable = "true"',
      'cheevos_username = ${quote(username)}',
      // Empty so RetroArch signs in with the token rather than a stale password.
      'cheevos_password = ""',
      'cheevos_token = ${quote(token)}',
      'cheevos_hardcore_mode_enable = "$hardcore"',
      '',
    ].join('\n');
  }
}
