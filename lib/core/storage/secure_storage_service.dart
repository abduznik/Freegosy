import 'dart:io' as io;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import '../platform/platform_info.dart';
import 'app_preferences.dart';
import 'secret_store.dart';

/// A wrapper around FlutterSecureStorage that falls back to SharedPreferences
/// if the system keyring is unavailable (common on Linux/Steam Deck).
/// 
/// "Multi-layer" protection:
/// 1. Try FlutterSecureStorage (Keychain/DPAPI/Libsecret).
/// 2. If it fails due to a PlatformException (e.g., keyring locked/missing), fallback to SharedPreferences.
/// 3. Log errors but never crash the app for a storage read.
/// 
/// NOTE: macOS uses SharedPreferences directly to avoid Keychain error -34018
/// caused by ad-hoc signing requirements.
class SecureStorageService {
  static final _storage = FlutterSecureStorage(
    aOptions: const AndroidOptions(),
    lOptions: const LinuxOptions(),
  );

  static PlatformInfo _platform = PlatformInfo.current;

  static SecretStore? _store;

  /// Use [store] for every secret instead of the platform's secure storage
  /// (a portable copy's per-PC credential file); null restores the default.
  static void useStore(SecretStore? store) => _store = store;

  static void configure({PlatformInfo? platform}) {
    _platform = platform ?? PlatformInfo.current;
  }

  static Future<String?> read(String key, AppPreferences prefs) async {
    final store = _store;
    if (store != null) {
      try {
        return await store.read(key);
      } catch (e) {
        debugPrint('[SecureStorage] Portable store error reading $key: $e');
        return null;
      }
    }
    // macOS bypass: Use SharedPreferences directly for stability in ad-hoc builds
    if (!kIsWeb && _platform.isMacOS) {
      return prefs.getString('macos_secure_$key');
    }

    try {
      // Layer 1: Secure Storage
      return await _storage.read(key: key);
    } on PlatformException catch (e) {
      // Layer 2: Fallback for keyring errors
      if (e.message?.contains('keyring') == true || e.code == 'null') {
        debugPrint('[SecureStorage] Keyring error on Linux, falling back to SharedPreferences: $e');
        return prefs.getString('fallback_secure_$key');
      }
      debugPrint('[SecureStorage] PlatformException reading $key: $e');
      return null;
    } catch (e) {
      debugPrint('[SecureStorage] Unexpected error reading $key: $e');
      return null;
    }
  }

  static Future<void> write(String key, String value, AppPreferences prefs) async {
    final store = _store;
    if (store != null) {
      try {
        await store.write(key, value);
      } catch (e) {
        debugPrint('[SecureStorage] Portable store error writing $key: $e');
      }
      return;
    }
    // macOS bypass: Use SharedPreferences directly for stability in ad-hoc builds
    if (!kIsWeb && _platform.isMacOS) {
      await prefs.setString('macos_secure_$key', value);
      return;
    }

    try {
      // Layer 1: Secure Storage
      await _storage.write(key: key, value: value);
    } on PlatformException catch (e) {
      // Layer 2: Fallback for keyring errors
      if (e.message?.contains('keyring') == true || e.code == 'null') {
        debugPrint('[SecureStorage] Keyring error on Linux, writing to SharedPreferences: $e');
        await prefs.setString('fallback_secure_$key', value);
      } else {
        debugPrint('[SecureStorage] PlatformException writing $key: $e');
      }
    } catch (e) {
      debugPrint('[SecureStorage] Unexpected error writing $key: $e');
    }
  }

  static Future<void> delete(String key, AppPreferences prefs) async {
    final store = _store;
    if (store != null) {
      try {
        await store.delete(key);
      } catch (e) {
        debugPrint('[SecureStorage] Portable store error deleting $key: $e');
      }
      return;
    }
    // macOS bypass: Use SharedPreferences directly for stability in ad-hoc builds
    if (!kIsWeb && _platform.isMacOS) {
      await prefs.remove('macos_secure_$key');
      return;
    }

    try {
      await _storage.delete(key: key);
      await prefs.remove('fallback_secure_$key');
    } catch (e) {
      debugPrint('[SecureStorage] Error deleting $key: $e');
      // Always try to clear the fallback even if secure storage fails
      try {
        await prefs.remove('fallback_secure_$key');
      } catch (_) {}
    }
  }
}
