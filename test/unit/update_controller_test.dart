import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/update/update_installer.dart';
import 'package:freegosy/core/update/update_models.dart';
import 'package:freegosy/core/update/update_service.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/providers/update_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  final List<int> body;
  int requests = 0;
  _Adapter(this.body);
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    requests++;
    return ResponseBody.fromBytes(body, 200, headers: {Headers.contentLengthHeader: ['${body.length}']});
  }

  @override
  void close({bool force = false}) {}
}

UpdateInfo infoFor(List<int> bytes, {String? sha, String url = 'https://github.com/x/y/releases/download/v1/a.AppImage'}) =>
    UpdateInfo(
      version: '9.9.9',
      tag: 'v9.9.9',
      prerelease: false,
      notes: '',
      pageUrl: 'https://github.com/x/y',
      assetName: 'a.AppImage',
      assetUrl: url,
      assetSize: bytes.length,
      sha256: sha,
    );

class _FakeService extends UpdateService {
  UpdateInfo? next;
  bool throwOnCheck = false;
  int checks = 0;
  int downloads = 0;
  String? lastRecordedSha;
  final InstallKind kind;
  final File file;
  _FakeService(this.kind, this.file) : super(supportDir: () async => Directory.systemTemp);

  @override
  InstallKind get installKind => kind;
  @override
  Future<UpdateInfo?> checkForUpdate(String v, UpdateChannel c, {String? recordedSha}) async {
    checks++;
    lastRecordedSha = recordedSha;
    if (throwOnCheck) throw Exception('offline');
    return next;
  }

  @override
  Future<File> download(UpdateInfo info, {void Function(double progress)? onProgress}) async {
    downloads++;
    onProgress?.call(1);
    return file;
  }
}

class _FakeInstaller extends UpdateInstaller {
  bool fail = false;
  int installs = 0;
  _FakeInstaller() : super(environment: {}, resolvedExecutable: '/x', pid: 1, spawnDetached: (_, __) async {});
  @override
  Future<void> installAndRestart(InstallKind kind, File file) async {
    installs++;
    if (fail) throw StateError('boom');
  }
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('fgupd_test'));
  tearDown(() async => tmp.delete(recursive: true));

  group('UpdateService.download', () {
    UpdateService svc(_Adapter a) =>
        UpdateService(dio: Dio()..httpClientAdapter = a, platform: const PlatformInfo('linux'), supportDir: () async => tmp);

    test('saves a file whose SHA-256 matches', () async {
      final bytes = utf8.encode('good build');
      final a = _Adapter(bytes);
      final f = await svc(a).download(infoFor(bytes, sha: sha256.convert(bytes).toString()));
      expect(await f.readAsBytes(), bytes);
    });

    test('reuses an already verified download', () async {
      final bytes = utf8.encode('good build');
      final a = _Adapter(bytes);
      final info = infoFor(bytes, sha: sha256.convert(bytes).toString());
      await svc(a).download(info);
      await svc(a).download(info);
      expect(a.requests, 1);
    });

    test('rejects and deletes a file with the wrong hash', () async {
      final bytes = utf8.encode('tampered');
      final a = _Adapter(bytes);
      await expectLater(svc(a).download(infoFor(bytes, sha: 'ab' * 32)), throwsStateError);
      expect(Directory('${tmp.path}/updates/v9.9.9/a.AppImage').existsSync(), isFalse);
      expect(File('${tmp.path}/updates/v9.9.9/a.AppImage').existsSync(), isFalse);
    });

    test('refuses a release with no checksum, without downloading', () async {
      final a = _Adapter([1]);
      await expectLater(svc(a).download(infoFor([1])), throwsStateError);
      expect(a.requests, 0);
    });

    test('refuses a non-GitHub host', () async {
      final a = _Adapter([1]);
      await expectLater(
          svc(a).download(infoFor([1], sha: 'ab' * 32, url: 'https://evil.example.com/a.AppImage')), throwsStateError);
      expect(a.requests, 0);
    });
  });

  group('UpdateInstaller AppImage', () {
    test('replaces the AppImage atomically, makes it executable and relaunches', () async {
      final target = File('${tmp.path}/Freegosy.AppImage')..writeAsStringSync('old');
      final update = File('${tmp.path}/new')..writeAsStringSync('new');
      List<String>? spawned;
      await UpdateInstaller(environment: {'APPIMAGE': target.path}, spawnDetached: (e, a) async => spawned = [e, ...a])
          .installAndRestart(InstallKind.appImage, update);
      expect(target.readAsStringSync(), 'new');
      expect(target.statSync().mode & 0x40, isNot(0));
      expect(File('${target.path}.update').existsSync(), isFalse);
      expect(spawned!.last, target.path);
    });

    test('leaves the old AppImage and no temp file when staging fails', () async {
      final target = File('${tmp.path}/Freegosy.AppImage')..writeAsStringSync('old');
      await expectLater(
        UpdateInstaller(environment: {'APPIMAGE': target.path}, spawnDetached: (_, __) async {})
            .installAndRestart(InstallKind.appImage, File('${tmp.path}/missing')),
        throwsA(anything),
      );
      expect(target.readAsStringSync(), 'old');
      expect(File('${target.path}.update').existsSync(), isFalse);
    });
  });

  group('UpdateController', () {
    late _FakeService service;
    late _FakeInstaller installer;
    late SharedPreferences prefs;
    late int? exitCode;

    Future<ProviderContainer> build({Map<String, Object> initial = const {}, InstallKind kind = InstallKind.appImage}) async {
      SharedPreferences.setMockInitialValues(initial);
      prefs = await SharedPreferences.getInstance();
      service = _FakeService(kind, File('${tmp.path}/dl'))..next = infoFor([1], sha: 'cafe');
      installer = _FakeInstaller();
      exitCode = null;
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        updateServiceProvider.overrideWithValue(service),
        updateInstallerProvider.overrideWithValue(installer),
        updateControllerProvider.overrideWith((ref) => UpdateController(ref, exitFn: (c) => exitCode = c)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('does nothing on launch when the check is disabled', () async {
      final c = await build(initial: {updateCheckPrefKey: false});
      await c.read(updateControllerProvider.notifier).checkOnLaunch();
      expect(service.checks, 0);
      expect(c.read(updateControllerProvider).status, UpdateStatus.idle);
    });

    test('launch check auto-downloads and ends up ready', () async {
      final c = await build();
      await c.read(updateControllerProvider.notifier).checkOnLaunch();
      expect(service.downloads, 1);
      expect(c.read(updateControllerProvider).status, UpdateStatus.ready);
    });

    test('with auto-download off it stops at available', () async {
      final c = await build(initial: {'update_auto_download': false});
      await c.read(updateControllerProvider.notifier).checkOnLaunch();
      expect(service.downloads, 0);
      expect(c.read(updateControllerProvider).status, UpdateStatus.available);
    });

    test('manual installs never auto-download', () async {
      final c = await build(kind: InstallKind.manual);
      await c.read(updateControllerProvider.notifier).checkOnLaunch();
      expect(service.downloads, 0);
      expect(c.read(updateControllerProvider).status, UpdateStatus.available);
    });

    test('no newer release -> upToDate', () async {
      final c = await build();
      service.next = null;
      await c.read(updateControllerProvider.notifier).check(manual: true);
      expect(c.read(updateControllerProvider).status, UpdateStatus.upToDate);
    });

    test('launch failures are silent, manual failures show an error', () async {
      final c = await build();
      service.throwOnCheck = true;
      final n = c.read(updateControllerProvider.notifier);
      await n.check(manual: false);
      expect(c.read(updateControllerProvider).status, UpdateStatus.idle);
      await n.check(manual: true);
      expect(c.read(updateControllerProvider).status, UpdateStatus.error);
    });

    test('restart records the applied digest only after a successful install, then exits', () async {
      final c = await build();
      final n = c.read(updateControllerProvider.notifier);
      await n.check(manual: true);
      await n.restartToUpdate();
      expect(installer.installs, 1);
      expect(exitCode, 0);
      expect(prefs.getString('update_applied_sha'), 'cafe');
      expect(prefs.getString('update_applied_version'), '9.9.9');
    });

    test('a failed install records nothing and does not exit', () async {
      final c = await build();
      installer.fail = true;
      final n = c.read(updateControllerProvider.notifier);
      await n.check(manual: true);
      await n.restartToUpdate();
      expect(exitCode, isNull);
      expect(prefs.getString('update_applied_sha'), isNull);
      expect(c.read(updateControllerProvider).status, UpdateStatus.error);
    });

    test('recorded digest is passed to the check only for the matching version', () async {
      final c = await build(initial: {'update_applied_sha': 'abc', 'update_applied_version': '0.0.0'});
      await c.read(updateControllerProvider.notifier).check(manual: true);
      expect(service.lastRecordedSha, 'abc'); // AppConstants.version is 0.0.0 in tests
      final c2 = await build(initial: {'update_applied_sha': 'abc', 'update_applied_version': '1.2.3'});
      await c2.read(updateControllerProvider.notifier).check(manual: true);
      expect(service.lastRecordedSha, isNull);
    });

    test('launchHandled starts false', () async {
      final c = await build();
      expect(c.read(updateControllerProvider.notifier).launchHandled, isFalse);
    });
  });
}
