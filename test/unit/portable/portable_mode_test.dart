import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/portable/portable_mode.dart';
import 'package:freegosy/core/portable/portable_paths.dart';
import 'package:freegosy/core/storage/secure_storage_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'portable_credential_store_test_helpers.dart';

class _Installed extends PathProviderPlatform {
  _Installed(this.base);
  final String base;
  @override
  Future<String?> getApplicationSupportPath() async => p.join(base, 'AppData');
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(base, 'Documents');
}

void main() {
  group('detectRoot', () {
    const windows = PlatformInfo('windows');
    final exe = p.windows.join(r'E:\Freegosy', 'freegosy.exe');

    test('portable when portable.txt sits beside the executable', () {
      expect(
          PortableMode.detectRoot(platform: windows, executable: exe, exists: (f) => f == r'E:\Freegosy\portable.txt'),
          r'E:\Freegosy');
    });

    test('not portable without the marker', () {
      expect(PortableMode.detectRoot(platform: windows, executable: exe, exists: (_) => false), isNull);
    });

    test('a portable.txt in an installer (Inno Setup) folder is ignored', () {
      for (final uninstaller in ['unins000.exe', 'unins000.dat']) {
        expect(
            PortableMode.detectRoot(
                platform: windows,
                executable: exe,
                exists: (f) => f == r'E:\Freegosy\portable.txt' || f == p.windows.join(r'E:\Freegosy', uninstaller)),
            isNull,
            reason: uninstaller);
      }
    });

    test('never portable off Windows', () {
      expect(
          PortableMode.detectRoot(platform: const PlatformInfo('linux'), executable: '/opt/freegosy/freegosy', exists: (_) => true),
          isNull);
    });
  });

  group('install', () {
    late io.Directory tmp;
    late PathProviderPlatform pathBefore;
    late SharedPreferencesStorePlatform prefsBefore;

    setUp(() async {
      tmp = await io.Directory.systemTemp.createTemp('portable_mode');
      pathBefore = PathProviderPlatform.instance;
      prefsBefore = SharedPreferencesStorePlatform.instance;
    });
    tearDown(() async {
      PathProviderPlatform.instance = pathBefore;
      SharedPreferencesStorePlatform.instance = prefsBefore;
      PortableMode.current = null;
      PortablePaths.active = null;
      SecureStorageService.useStore(null);
      await tmp.delete(recursive: true);
    });

    test('creates data folders and redirects path_provider and SharedPreferences', () async {
      final root = p.join(tmp.path, 'Freegosy');
      await io.Directory(root).create();
      final mode = await PortableMode.install(root,
          previous: _Installed(tmp.path), credentials: (dir) => fakeCredentialStore(dir));

      for (final sub in ['support', 'documents', 'temp', 'credentials']) {
        expect(io.Directory(p.join(root, 'userdata', sub)).existsSync(), isTrue, reason: sub);
      }
      expect(await PathProviderPlatform.instance.getApplicationSupportPath(), p.join(root, 'userdata', 'support'));
      expect(SharedPreferencesStorePlatform.instance, same(mode.prefsStore));
      expect(mode.prefsStore.file.path, p.join(root, 'userdata', 'shared_preferences.json'));
      expect(PortableMode.current, same(mode));
      expect(PortablePaths.active?.root, root);
      expect(mode.startedEmpty, isTrue);
      expect(mode.installedSupportDir, p.join(tmp.path, 'AppData'));
      expect(mode.installedDocumentsDir, p.join(tmp.path, 'Documents'));
    });

    test('startedEmpty is false when settings already exist', () async {
      final root = p.join(tmp.path, 'Freegosy');
      await io.File(p.join(root, 'userdata', 'shared_preferences.json')).create(recursive: true);
      final mode = await PortableMode.install(root,
          previous: _Installed(tmp.path), credentials: (dir) => fakeCredentialStore(dir));
      expect(mode.startedEmpty, isFalse);
    });

    test('a documents\\x.hive.import becomes x.hive, replacing an old x.hive', () async {
      final root = p.join(tmp.path, 'Freegosy');
      final docs = p.join(root, 'userdata', 'documents');
      await io.File(p.join(docs, 'x.hive')).create(recursive: true).then((f) => f.writeAsString('old'));
      await io.File(p.join(docs, 'x.hive.import')).writeAsString('imported');
      await PortableMode.install(root, previous: _Installed(tmp.path), credentials: (dir) => fakeCredentialStore(dir));
      expect(io.File(p.join(docs, 'x.hive')).readAsStringSync(), 'imported');
      expect(io.File(p.join(docs, 'x.hive.import')).existsSync(), isFalse);
    });

    test('a folder that cannot be written throws before anything is redirected', () async {
      final root = p.join(tmp.path, 'Freegosy');
      // A file where data\ should be makes creating the folder fail.
      await io.File(p.join(root, 'userdata')).create(recursive: true);
      await expectLater(
          PortableMode.install(root, previous: _Installed(tmp.path), credentials: (dir) => fakeCredentialStore(dir)),
          throwsA(isA<PortableModeException>()));
      expect(PathProviderPlatform.instance, same(pathBefore));
      expect(PortableMode.current, isNull);
    });

    // Windows' folder Read-only box marks the files inside, while new files
    // can still be created — the probe file alone doesn't catch it.
    Future<void> makeReadOnly(String file, bool readOnly) => io.Platform.isWindows
        ? io.Process.run('attrib', [readOnly ? '+R' : '-R', file])
        : io.Process.run('chmod', [readOnly ? '444' : '644', file]);

    for (final file in [
      ['shared_preferences.json'],
      ['documents', 'freegosy_backups.hive'],
    ]) {
      test('a read-only ${file.last} is reported before anything is redirected', () async {
        final root = p.join(tmp.path, 'Freegosy');
        final path = p.joinAll([root, 'userdata', ...file]);
        await io.File(path).create(recursive: true);
        await makeReadOnly(path, true);
        addTearDown(() => makeReadOnly(path, false));

        await expectLater(
            PortableMode.install(root, previous: _Installed(tmp.path), credentials: (dir) => fakeCredentialStore(dir)),
            throwsA(isA<PortableModeException>()));
        expect(PathProviderPlatform.instance, same(pathBefore));
        expect(PortableMode.current, isNull);
      });
    }

  });

  test('restart closes Hive and flushes settings before starting the new process', () async {
    final calls = <String>[];
    PortableMode.launchArgs = ['--fullscreen'];
    await PortableMode.restart(
      closeStorage: () async => calls.add('close'),
      start: (exe, args) async => calls.add('start ${args.join(' ')}'),
      exit: (code) => calls.add('exit $code'),
    );
    expect(calls, ['close', 'start --fullscreen', 'exit 0']);
    PortableMode.launchArgs = const [];
  });
}
