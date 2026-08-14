import '../romm/romm_models.dart';
import '../storage/app_preferences.dart';
import '../storage/secure_storage_service.dart';

/// Builds a [RomMConfig] for the headless CLI the same way the GUI app's
/// `rommConfigProvider` does — base URL/username from prefs, and
/// password/token/API key from the OS-encrypted secure storage the user
/// already populated by logging in through the UI. The CLI runs inside the
/// real Flutter engine (see `lib/main_cli.dart`), so `flutter_secure_storage`
/// works exactly as it does for the GUI; no separate credential entry is
/// needed for headless use.
Future<RomMConfig> loadCliRommConfig(AppPreferences prefs) async {
  final baseUrl = prefs.getString('rommBaseUrl') ?? '';
  final username = prefs.getString('rommUsername') ?? '';
  final password = await SecureStorageService.read('rommPassword', prefs) ?? '';
  final token = await SecureStorageService.read('rommAuthToken', prefs);
  final apiKey = await SecureStorageService.read('rommApiKey', prefs) ?? '';
  final trustSelfSigned = prefs.getBool('rommTrustSelfSigned') ?? false;

  return RomMConfig(
    baseUrl: baseUrl,
    username: username,
    password: password,
    token: token,
    apiKey: apiKey,
    trustSelfSigned: trustSelfSigned,
  );
}
