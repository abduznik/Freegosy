import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// A wrapper around FlutterSecureStorage that falls back to SharedPreferences
/// if the system keyring is unavailable (common on Linux/Steam Deck).
/// 
/// "Multi-layer" protection:
/// 1. Try FlutterSecureStorage (Keychain/DPAPI/Libsecret).
/// 2. If it fails due to a PlatformException (e.g., keyring locked/missing), fallback to SharedPreferences.
/// 3. Log errors but never crash the app for a storage read.
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> read(String key) async {
    try {
      // Layer 1: Secure Storage
      return await _storage.read(key: key);
    } on PlatformException catch (e) {
      // Layer 2: Fallback for keyring errors
      if (e.message?.contains('keyring') == true || e.code == 'null') {
        debugPrint('[SecureStorage] Keyring error on Linux, falling back to SharedPreferences: $e');
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString('fallback_secure_$key');
      }
      debugPrint('[SecureStorage] PlatformException reading $key: $e');
      return null;
    } catch (e) {
      debugPrint('[SecureStorage] Unexpected error reading $key: $e');
      return null;
    }
  }

  static Future<void> write(String key, String value) async {
    try {
      // Layer 1: Secure Storage
      await _storage.write(key: key, value: value);
    } on PlatformException catch (e) {
      // Layer 2: Fallback for keyring errors
      if (e.message?.contains('keyring') == true || e.code == 'null') {
        debugPrint('[SecureStorage] Keyring error on Linux, writing to SharedPreferences: $e');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fallback_secure_$key', value);
      } else {
        debugPrint('[SecureStorage] PlatformException writing $key: $e');
      }
    } catch (e) {
      debugPrint('[SecureStorage] Unexpected error writing $key: $e');
    }
  }

  static Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fallback_secure_$key');
    } catch (e) {
      debugPrint('[SecureStorage] Error deleting $key: $e');
      // Always try to clear the fallback even if secure storage fails
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('fallback_secure_$key');
      } catch (_) {}
    }
  }
}
