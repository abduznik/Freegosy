import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../retroachievements/retroachievements_emulator_login.dart' show kRetroArchAchievementsConfigFileName;
import '../storage/secret_store.dart';
import 'json_file_preferences_store.dart';
import 'portable_handover.dart';
import 'portable_mode.dart';
import 'portable_paths.dart';

/// Copies Freegosy's data into and out of a portable copy. Copies, never
/// moves; the marker is written (or deleted) last, so a failure leaves the
/// copy as it was.
class PortableMigration {
  PortableMigration({
    required this.root,
    required this.installedSupportDir,
    required this.installedDocumentsDir,
    bool Function(String path)? exists,
    DateTime Function()? now,
  })  : _paths = PortablePaths(root: root, exists: exists),
        _now = now ?? DateTime.now;

  final String root;
  final String installedSupportDir;
  final String installedDocumentsDir;
  final PortablePaths _paths;
  final DateTime Function() _now;

  static const defaultFolders = ['ROMs', 'Emulators'];

  /// Freegosy's own Hive boxes in Documents (Hive shares that folder with other
  /// apps, so nothing else may be touched). A new box must be added here.
  static const hiveBoxes = ['freegosy_backups', 'rom_mappings_v2'];
  static const _prefsFile = 'shared_preferences.json';
  static const _secureFile = 'flutter_secure_storage.dat';

  /// Files that belong to one PC and are never copied, at any depth: the RA
  /// token RetroArch reads (tokens are per PC; see the portable mode spec).
  static const perPcFiles = {kRetroArchAchievementsConfigFileName};

  /// Suffix for Hive files copied into a running portable copy; see
  /// [PortableMode.install], which swaps them in before Hive opens anything.
  static const importSuffix = '.import';

  String get dataDir => p.join(root, PortableMode.dataFolderName);
  String get markerPath => p.join(root, PortableMode.markerName);
  String get _dataSupport => p.join(dataDir, 'support');
  String get _dataDocuments => p.join(dataDir, 'documents');
  String get _installedPrefs => p.join(installedSupportDir, _prefsFile);

  bool get installedHasData => io.File(_installedPrefs).existsSync();

  /// When the installed copy's settings were last saved; null if it has none.
  DateTime? get installedDataModified {
    final file = io.File(_installedPrefs);
    return file.existsSync() ? file.lastModifiedSync() : null;
  }

  /// Set in a new portable copy's settings when it was made portable without
  /// copying, so it doesn't then offer to import the PC's settings.
  static const skipImportOfferKey = 'portable_skip_import_offer';

  /// When this copy's own settings (`userdata\shared_preferences.json`) were last
  /// saved; null if it has none.
  DateTime? get portableDataModified {
    final file = io.File(p.join(dataDir, _prefsFile));
    return file.existsSync() ? file.lastModifiedSync() : null;
  }

  /// Makes this copy portable without copying anything: an empty data folder
  /// (or the one left from an earlier portable period, whose settings are
  /// reused), then the marker, written last.
  Future<void> makePortableFresh() async {
    await io.Directory(dataDir).create(recursive: true);
    final prefs = p.join(dataDir, _prefsFile);
    if (!io.File(prefs).existsSync()) await _writePrefs(prefs, {'flutter.$skipImportOfferKey': true}, (v) => v);
    await io.File(markerPath).writeAsString('');
  }

  /// The default folders ([defaultFolders]) the PC's install has of its own.
  List<String> get installedDefaultFolders =>
      [for (final name in defaultFolders) if (io.Directory(p.join(installedSupportDir, name)).existsSync()) name];

  Future<void> toPortable({
    required bool includeDefaultFolders,
    required SecretStore installedSecrets,
    required SecretStore portableSecrets,
  }) async {
    final created = !io.Directory(dataDir).existsSync();
    try {
      final values = await _copyIn(includeDefaultFolders: includeDefaultFolders);
      await _writePrefs(p.join(dataDir, _prefsFile), values, _paths.toStored);
      for (final e in (await installedSecrets.readAll()).entries) {
        await portableSecrets.write(e.key, e.value);
      }
      await io.File(markerPath).writeAsString('');
    } catch (_) {
      if (created && io.Directory(dataDir).existsSync()) await io.Directory(dataDir).delete(recursive: true);
      rethrow;
    }
  }

  /// For a running portable copy that started empty: copies the files and
  /// returns the settings to put into its store. Hive files arrive as
  /// `<name>.hive.import` because the running copy has its own open; the next
  /// start swaps them in. Secrets follow after the restart
  /// ([PortableHandover.pendingImportSecretsKey]).
  Future<Map<String, Object>> importInstalled({required bool includeDefaultFolders}) async {
    final secureTarget = p.join(_dataSupport, _secureFile);
    var triedSecure = false;
    try {
      final values = await _copyIn(includeDefaultFolders: includeDefaultFolders, hiveSuffix: importSuffix);
      final secure = io.File(p.join(installedSupportDir, _secureFile));
      if (secure.existsSync()) {
        triedSecure = true;
        await secure.copy(secureTarget);
      }
      values['flutter.${PortableHandover.pendingImportSecretsKey}'] = true;
      return values;
    } catch (_) {
      // PortableMode.install swaps .import files in at the next start, so a
      // half-finished import must not leave any behind.
      final leftovers = [
        for (final box in hiveBoxes) p.join(_dataDocuments, '$box.hive$importSuffix'),
        if (triedSecure) secureTarget,
      ];
      for (final path in leftovers) {
        try {
          if (io.FileSystemEntity.typeSync(path) == io.FileSystemEntityType.file) await io.File(path).delete();
        } catch (error) {
          debugPrint('[Portable] Import cleanup could not remove $path: $error');
        }
      }
      rethrow;
    }
  }

  Future<Map<String, Object>> _copyIn({required bool includeDefaultFolders, String hiveSuffix = ''}) async {
    final values = _readPrefs(_installedPrefs);
    await _copyTree(installedSupportDir, _dataSupport,
        skip: {_prefsFile, _secureFile, if (!includeDefaultFolders) ...defaultFolders});
    if (!includeDefaultFolders) _keepDefaultFolders(values, installedSupportDir);
    await _copyHive(installedDocumentsDir, _dataDocuments, hiveSuffix);
    values['flutter.${PortableHandover.rebaseBackupsFromKey}'] = installedSupportDir;
    values['flutter.${PortableHandover.rebaseBackupsToKey}'] = _dataSupport;
    return values;
  }

  /// Puts this copy's data back on the PC. The PC's existing support folder
  /// is renamed aside as a backup, except its own default ROM and emulator
  /// folders ([defaultFolders]): those are the PC's games and emulator saves,
  /// not settings, so they stay in use and the stick's copies never replace
  /// them.
  Future<void> toInstalled({required bool includeDefaultFolders}) async {
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(_now());
    final renamed = <String, String>{}; // backup path -> original path
    final written = <String>[];
    final kept = <String, String>{}; // PC folder now in use -> its place in the backup
    try {
      if (io.Directory(installedSupportDir).existsSync()) {
        final aside = '$installedSupportDir.before-portable-$stamp';
        await io.Directory(installedSupportDir).rename(aside);
        renamed[aside] = installedSupportDir;
        await io.Directory(installedSupportDir).create(recursive: true);
        written.add(installedSupportDir);
        for (final name in defaultFolders) {
          final inBackup = p.join(aside, name);
          if (!io.Directory(inBackup).existsSync()) continue;
          final inUse = p.join(installedSupportDir, name);
          await io.Directory(inBackup).rename(inUse); // same folder, so same drive
          kept[inUse] = inBackup;
        }
      }
      for (final hive in _hiveFiles(installedDocumentsDir).toList()) {
        final aside = '$hive.before-portable-$stamp';
        await io.File(hive).rename(aside);
        renamed[aside] = hive;
      }

      final values = _readPrefs(p.join(dataDir, _prefsFile));
      if (!written.contains(installedSupportDir)) written.add(installedSupportDir);
      final pcFolders = {for (final path in kept.keys) p.basename(path)};
      await _copyTree(_dataSupport, installedSupportDir,
          skip: {_secureFile, ...(includeDefaultFolders ? pcFolders : defaultFolders)});
      if (!includeDefaultFolders) _keepDefaultFolders(values, _dataSupport, except: pcFolders);
      values['flutter.${PortableHandover.pendingCredentialsKey}'] = dataDir;
      values['flutter.${PortableHandover.rebaseBackupsFromKey}'] = _dataSupport;
      values['flutter.${PortableHandover.rebaseBackupsToKey}'] = installedSupportDir;
      await _writePrefs(_installedPrefs, values, _paths.fromStored);
      for (final hive in _hiveFiles(_dataDocuments)) {
        final target = p.join(installedDocumentsDir, p.basename(hive));
        written.add(target);
        await io.File(hive).copy(target);
      }
      await io.File(markerPath).delete();
    } catch (_) {
      await _rollback(written, renamed, kept);
      rethrow;
    }
  }

  /// Best effort: a failing cleanup step must not hide the original error or
  /// stop the remaining backups from being renamed back. The PC's own folders
  /// go back into the backup first; if one can't, the folder holding it is
  /// left alone rather than deleted.
  Future<void> _rollback(List<String> written, Map<String, String> renamed, Map<String, String> kept) async {
    final stuck = <String>[];
    for (final e in kept.entries) {
      try {
        await io.Directory(e.key).rename(e.value);
      } catch (error) {
        stuck.add(e.key);
        debugPrint('[Portable] Rollback could not move ${e.key} back to ${e.value}: $error');
      }
    }
    for (final path in written.reversed) {
      if (stuck.any((s) => p.equals(s, path) || p.isWithin(path, s))) {
        debugPrint('[Portable] Rollback left $path in place: it still holds files of this PC');
        continue;
      }
      try {
        final type = io.FileSystemEntity.typeSync(path);
        if (type == io.FileSystemEntityType.directory) await io.Directory(path).delete(recursive: true);
        if (type == io.FileSystemEntityType.file) await io.File(path).delete();
      } catch (error) {
        debugPrint('[Portable] Rollback could not remove $path: $error');
      }
    }
    for (final e in renamed.entries) {
      try {
        if (io.FileSystemEntity.typeSync(e.key) == io.FileSystemEntityType.directory) {
          await io.Directory(e.key).rename(e.value);
        } else if (io.File(e.key).existsSync()) {
          await io.File(e.key).rename(e.value);
        }
      } catch (error) {
        debugPrint('[Portable] Rollback could not restore ${e.value}; the PC data is left at ${e.key}: $error');
      }
    }
  }

  /// Bytes in the default ROM and emulator folders (installed or portable).
  Future<int> defaultFoldersSize({required bool portable}) async {
    var total = 0;
    for (final name in defaultFolders) {
      final dir = io.Directory(p.join(portable ? _dataSupport : installedSupportDir, name));
      if (!dir.existsSync()) continue;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is io.File) total += await e.length();
      }
    }
    return total;
  }

  /// Points the settings at [fromSupport]'s default folders, which aren't
  /// copied, unless already set or the target has its own ([except]).
  void _keepDefaultFolders(Map<String, Object> values, String fromSupport, {Set<String> except = const {}}) {
    const keys = {'ROMs': 'flutter.romsRootPath', 'Emulators': 'flutter.emulatorsRootPath'};
    for (final e in keys.entries) {
      if (except.contains(e.key)) continue;
      final folder = p.join(fromSupport, e.key);
      if (io.Directory(folder).existsSync() && !values.containsKey(e.value)) values[e.value] = folder;
    }
  }

  Map<String, Object> _readPrefs(String path) {
    final file = io.File(path);
    if (!file.existsSync()) return {};
    final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return {
      for (final e in raw.entries)
        if (e.value != null) e.key: e.value is List ? List<String>.from(e.value as List) : e.value as Object,
    };
  }

  Future<void> _writePrefs(String path, Map<String, Object> values, String Function(String) convert) async {
    await io.File(path).parent.create(recursive: true);
    await io.File(path).writeAsString(
        jsonEncode({for (final e in values.entries) e.key: JsonFilePreferencesStore.mapPaths(e.value, convert)}),
        flush: true);
  }

  Iterable<String> _hiveFiles(String dir) => io.Directory(dir).existsSync()
      ? io.Directory(dir).listSync().whereType<io.File>().map((f) => f.path).where((f) => hiveBoxes.contains(p.basenameWithoutExtension(f)) && f.endsWith('.hive'))
      : const [];

  Future<void> _copyHive(String from, String to, String suffix) async {
    await io.Directory(to).create(recursive: true);
    for (final hive in _hiveFiles(from)) {
      await io.File(hive).copy(p.join(to, '${p.basename(hive)}$suffix'));
    }
  }

  Future<void> _copyTree(String from, String to, {Set<String> skip = const {}}) async {
    await io.Directory(to).create(recursive: true);
    if (!io.Directory(from).existsSync()) return;
    await for (final entity in io.Directory(from).list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (skip.contains(name) || perPcFiles.contains(name)) continue;
      final target = p.join(to, name);
      if (entity is io.Directory) {
        await _copyTree(entity.path, target);
      } else if (entity is io.File) {
        await entity.copy(target);
      }
    }
  }
}
