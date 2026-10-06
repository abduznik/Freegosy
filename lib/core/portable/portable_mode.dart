import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../platform/platform_info.dart';
import '../storage/secure_storage_service.dart';
import 'json_file_preferences_store.dart';
import 'portable_credential_store.dart';
import 'portable_path_provider.dart';
import 'portable_paths.dart';

class PortableModeException implements Exception {
  PortableModeException(this.root, this.reason);
  final String root;
  final Object reason;
  @override
  String toString() => "This portable copy can't write to $root: $reason";
}

/// A Windows copy with `portable.txt` beside `freegosy.exe` keeps everything
/// in `<folder>\userdata` (see the portable mode spec). [install] must run before
/// anything reads settings or app folders.
class PortableMode {
  PortableMode._({
    required this.root,
    required this.startedEmpty,
    required this.installedSupportDir,
    required this.installedDocumentsDir,
    required this.prefsStore,
    required this.credentials,
  });

  static const markerName = 'portable.txt';

  /// Not `data`: the Windows build keeps its own files (`app.so`,
  /// `flutter_assets`) there.
  static const dataFolderName = 'userdata';

  static PortableMode? current;

  /// The arguments Freegosy was started with, for [restart].
  static List<String> launchArgs = const [];

  final String root;
  String get dataDir => p.join(root, dataFolderName);
  String get markerPath => p.join(root, markerName);

  /// True when `userdata\shared_preferences.json` didn't exist at start.
  final bool startedEmpty;

  /// The PC's normal (non-portable) folders, from the original provider.
  final String installedSupportDir;
  final String installedDocumentsDir;

  final JsonFilePreferencesStore prefsStore;
  final PortableCredentialStore credentials;

  static String? detectRoot({PlatformInfo? platform, String? executable, bool Function(String path)? exists}) {
    final info = platform ?? PlatformInfo.current;
    if (!info.isWindows) return null;
    final root = p.windows.dirname(executable ?? io.Platform.resolvedExecutable);
    final has = exists ?? (String f) => io.File(f).existsSync();
    if (!has(p.windows.join(root, markerName))) return null;
    if (isInstallerCopy(root, exists: has)) {
      debugPrint('[Portable] Ignoring $markerName: $root is an installed copy, and the next '
          'installer run would delete its data folder. Use the zip version for portable mode.');
      return null;
    }
    return root;
  }

  /// The uninstaller Inno Setup leaves beside the app. Installer copies can't
  /// be portable: the next installer run deletes everything in their folder.
  static const installerFiles = ['unins000.exe', 'unins000.dat'];

  /// Whether [dir] holds a copy installed by Freegosy's installer.
  static bool isInstallerCopy(String dir, {bool Function(String path)? exists}) {
    final has = exists ?? (String f) => io.File(f).existsSync();
    return installerFiles.any((name) => has(p.windows.join(dir, name)));
  }

  static Future<PortableMode> install(
    String root, {
    PathProviderPlatform? previous,
    PortableCredentialStore Function(String dir)? credentials,
    void Function(String message)? onProblem,
  }) async {
    final dataDir = p.join(root, dataFolderName);
    try {
      for (final sub in ['support', 'documents', 'temp', 'credentials']) {
        await io.Directory(p.join(dataDir, sub)).create(recursive: true);
      }
      final probe = io.File(p.join(dataDir, '.write-test'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      // A new file can be created even when the existing ones are read-only
      // (the folder's Read-only box marks its files), so try those too.
      await _probeWritable(io.File(p.join(dataDir, 'shared_preferences.json')));
      final hiveFiles = io.Directory(p.join(dataDir, 'documents'))
          .listSync()
          .whereType<io.File>()
          .where((f) => f.path.endsWith('.hive'));
      for (final file in hiveFiles) {
        await _probeWritable(file);
      }
      // Hive files imported from the PC's install by a running portable copy
      // are swapped in now, before Hive can open anything.
      final documents = io.Directory(p.join(dataDir, 'documents'));
      for (final entity in documents.listSync().whereType<io.File>().toList()) {
        if (!entity.path.endsWith('.hive.import')) continue;
        final target = io.File(entity.path.substring(0, entity.path.length - '.import'.length));
        await entity.rename(target.path);
      }
    } catch (e) {
      throw PortableModeException(root, e);
    }

    final original = previous ?? PathProviderPlatform.instance;
    final installedSupport = await original.getApplicationSupportPath() ?? '';
    final installedDocuments = await original.getApplicationDocumentsPath() ?? '';

    final prefsFile = io.File(p.join(dataDir, 'shared_preferences.json'));
    final startedEmpty = !prefsFile.existsSync();
    final paths = PortablePaths(root: root);
    final store = JsonFilePreferencesStore(prefsFile,
        toStored: paths.toStored, fromStored: paths.fromStored, onProblem: onProblem);
    final creds = (credentials ?? PortableCredentialStore.forThisPc)(p.join(dataDir, 'credentials'));

    PortablePaths.active = paths;
    PathProviderPlatform.instance = PortablePathProvider(dataDir: dataDir, previous: original);
    SharedPreferencesStorePlatform.instance = store;
    SecureStorageService.useStore(creds);
    debugPrint('[Portable] Portable mode: data in $dataDir');

    return current = PortableMode._(
      root: root,
      startedEmpty: startedEmpty,
      installedSupportDir: installedSupport,
      installedDocumentsDir: installedDocuments,
      prefsStore: store,
      credentials: creds,
    );
  }

  /// Opens [file] for writing without changing it; throws if it's read-only.
  static Future<void> _probeWritable(io.File file) async {
    if (!file.existsSync()) return;
    final handle = await file.open(mode: io.FileMode.append);
    await handle.close();
  }

  /// Whether [dir] accepts new files (false for an installer's Program Files).
  static bool folderWritable(String dir) {
    final probe = io.File(p.join(dir, '.freegosy-write-test'));
    try {
      probe.writeAsStringSync('ok', flush: true);
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Starts a new Freegosy with the same arguments and exits this one.
  /// Settings are flushed and Hive is closed first: the new process swaps
  /// imported Hive files in and takes Hive's lock files at once, possibly
  /// before this one has exited. The parameters are for tests.
  static Future<void> restart({
    Future<void> Function()? closeStorage,
    Future<void> Function(String executable, List<String> args)? start,
    void Function(int code)? exit,
  }) async {
    await current?.prefsStore.flush();
    await (closeStorage ?? Hive.close)();
    await (start ?? _startDetached)(io.Platform.resolvedExecutable, launchArgs);
    (exit ?? io.exit)(0);
  }

  static Future<void> _startDetached(String executable, List<String> args) =>
      io.Process.start(executable, args, mode: io.ProcessStartMode.detached);
}
