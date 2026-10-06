import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../save/backup_entry.dart';
import '../storage/app_preferences.dart';
import '../storage/secret_store.dart';
import 'portable_credential_store.dart';

/// The platform's secure storage as a [SecretStore].
class FlutterSecretStore implements SecretStore {
  const FlutterSecretStore();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}

/// Steps of switching portable mode on or off that can only run after the
/// restart, when storage points at the new place:
/// - [pendingCredentialsKey] (normal start after "Stop being portable"): copy
///   this PC's secrets from the stick's credential file into secure storage.
/// - [pendingImportSecretsKey] (portable start after an import): the PC's
///   secure-storage file was copied into `userdata\support`; move its secrets into
///   the per-PC credential file and empty it.
/// - [rebaseBackupsFromKey]/[rebaseBackupsToKey]: backup zips moved with the
///   app support folder; point the backup index at the new place.
class PortableHandover {
  static const pendingCredentialsKey = 'portable_pending_credentials';
  static const pendingImportSecretsKey = 'portable_pending_import_secrets';
  static const rebaseBackupsFromKey = 'portable_rebase_backups_from';
  static const rebaseBackupsToKey = 'portable_rebase_backups_to';

  static Future<void> run({
    required AppPreferences prefs,
    required Box<List> backups,
    required SecretStore platformSecrets,
    SecretStore? portableSecrets,
    SecretStore Function(String credentialsDir)? credentialsIn,
  }) async {
    final dataDir = prefs.getString(pendingCredentialsKey);
    if (dataDir != null) {
      final credentialsDir = p.join(dataDir, 'credentials');
      try {
        if (await io.Directory(credentialsDir).exists()) {
          final store = (credentialsIn ?? PortableCredentialStore.forThisPc)(
            credentialsDir,
          );
          for (final e in (await store.readAll()).entries) {
            await platformSecrets.write(e.key, e.value);
          }
        }
      } catch (e) {
        debugPrint('[Portable] Could not bring credentials over: $e');
      }
      await _safeRemove(prefs, pendingCredentialsKey);
    }

    if (prefs.getBool(pendingImportSecretsKey) == true) {
      try {
        if (portableSecrets == null) {
          debugPrint('[Portable] No per-PC store to import credentials into.');
        } else {
          final secrets = await platformSecrets.readAll();
          for (final e in secrets.entries) {
            await portableSecrets.write(e.key, e.value);
            await platformSecrets.delete(e.key);
          }
        }
      } catch (e) {
        debugPrint('[Portable] Could not import credentials: $e');
      }
      await _safeRemove(prefs, pendingImportSecretsKey);
    }

    final from = prefs.getString(rebaseBackupsFromKey);
    final to = prefs.getString(rebaseBackupsToKey);
    if (from != null && to != null) {
      try {
        await rebaseBackups(backups, from, to);
      } catch (e) {
        debugPrint('[Portable] Could not rebase backup paths: $e');
      }
    }
    if (from != null) await _safeRemove(prefs, rebaseBackupsFromKey);
    if (to != null) await _safeRemove(prefs, rebaseBackupsToKey);
  }

  static Future<void> _safeRemove(AppPreferences prefs, String key) async {
    try {
      await prefs.remove(key);
    } catch (e) {
      debugPrint('[Portable] Could not clear $key: $e');
    }
  }

  static Future<void> rebaseBackups(
    Box<List> backups,
    String fromDir,
    String toDir,
  ) async {
    for (final key in backups.keys.toList()) {
      final entries = backups.get(key)?.cast<BackupEntry>();
      if (entries == null) continue;
      var changed = false;
      final rebased = [
        for (final e in entries)
          if (p.isWithin(fromDir, e.localZipPath))
            () {
              changed = true;
              return BackupEntry(
                timestamp: e.timestamp,
                md5Hash: e.md5Hash,
                localZipPath: p.join(
                  toDir,
                  p.relative(e.localZipPath, from: fromDir),
                ),
                isSynced: e.isSynced,
              );
            }()
          else
            e,
      ];
      if (changed) await backups.put(key, rebased);
    }
  }
}
