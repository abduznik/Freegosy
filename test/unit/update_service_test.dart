import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/update/update_installer.dart';
import 'package:freegosy/core/update/update_models.dart';
import 'package:freegosy/core/update/update_service.dart';
import 'package:freegosy/core/update/version_compare.dart';
import 'dart:io';

Map<String, dynamic> release(String tag, {bool pre = false, bool draft = false, List<String> assets = const []}) => {
      'tag_name': tag,
      'prerelease': pre,
      'draft': draft,
      'html_url': 'https://github.com/abduznik/Freegosy/releases/tag/$tag',
      'assets': [
        for (final a in assets)
          {'name': a, 'browser_download_url': 'https://x/$tag/$a', 'size': 10, 'digest': 'sha256:ABC'},
      ],
    };

void main() {
  group('VersionCompare', () {
    test('orders numerically, not lexically', () {
      expect(VersionCompare.isNewer('v0.10.0', '0.9.9'), isTrue);
      expect(VersionCompare.isNewer('0.6.1', 'v0.6.1'), isFalse);
    });
    test('pre-release suffix sorts before the plain release', () {
      expect(VersionCompare.isNewer('0.6.1', '0.6.1-pre'), isTrue);
      expect(VersionCompare.isNewer('0.6.1-pre', '0.6.1'), isFalse);
      expect(VersionCompare.isNewer('0.6.2-pre', '0.6.1'), isTrue);
    });
    test('garbage never counts as newer', () {
      expect(VersionCompare.isNewer('nightly', '0.6.1'), isFalse);
    });
  });

  group('pickUpdate', () {
    final releases = [
      release('v0.7.0-pre', pre: true, assets: ['Freegosy-linux-x86_64.AppImage']),
      release('v0.6.2', assets: ['Freegosy-linux-x86_64.AppImage', 'freegosy-linux-x64.tar.gz']),
      release('v0.9.0', draft: true),
    ];
    test('stable channel skips pre-releases and drafts', () {
      final u = UpdateService.pickUpdate(releases, '0.6.1', UpdateChannel.stable, InstallKind.appImage)!;
      expect(u.version, '0.6.2');
      expect(u.assetName, 'Freegosy-linux-x86_64.AppImage');
      expect(u.sha256, 'abc');
    });
    test('pre-release channel takes the highest version', () {
      final u = UpdateService.pickUpdate(releases, '0.6.1', UpdateChannel.prerelease, InstallKind.appImage)!;
      expect(u.version, '0.7.0-pre');
      expect(u.prerelease, isTrue);
    });
    test('null when current is newest', () {
      expect(UpdateService.pickUpdate(releases, '0.6.2', UpdateChannel.stable, InstallKind.appImage), isNull);
    });
    test('same-version rebuild is offered only when digests are known and differ', () {
      final r = [release('v0.6.2', assets: ['Freegosy-linux-x86_64.AppImage'])]; // digest 'abc'
      UpdateInfo? pick(String? installed) =>
          UpdateService.pickUpdate(r, '0.6.2', UpdateChannel.stable, InstallKind.appImage, installedSha: installed);
      expect(pick('old')?.isRebuild, isTrue);
      expect(pick('abc'), isNull);
      expect(pick(null), isNull);
    });
    test('manual installs get no asset', () {
      final u = UpdateService.pickUpdate(releases, '0.6.1', UpdateChannel.stable, InstallKind.manual)!;
      expect(u.hasAsset, isFalse);
    });
    test('windows portable picks the zip', () {
      final r = [release('v0.6.2', assets: ['Freegosy-Installer.exe', 'freegosy-windows-x64.zip'])];
      final u = UpdateService.pickUpdate(r, '0.6.1', UpdateChannel.stable, InstallKind.windowsPortable)!;
      expect(u.assetName, 'freegosy-windows-x64.zip');
    });
  });

  group('installKind', () {
    UpdateService svc(PlatformInfo p, {String exe = '/x/freegosy', bool Function(String)? exists}) => UpdateService(
          platform: p,
          supportDir: () async => Directory.systemTemp,
          resolvedExecutable: () => exe,
          fileExists: exists,
        );
    test('linux with APPIMAGE is appImage, without is manual', () {
      expect(svc(const PlatformInfo('linux', environment: {'APPIMAGE': '/a/F.AppImage'})).installKind, InstallKind.appImage);
      expect(svc(const PlatformInfo('linux')).installKind, InstallKind.manual);
    });
    test('windows needs the uninstaller beside the exe', () {
      expect(svc(const PlatformInfo('windows'), exe: '/app/freegosy.exe', exists: (_) => true).installKind,
          InstallKind.windowsInstaller);
      expect(svc(const PlatformInfo('windows'), exe: '/app/freegosy.exe', exists: (_) => false).installKind,
          InstallKind.windowsPortable);
    });
    test('macOS needs to run from a .app bundle', () {
      expect(svc(const PlatformInfo('macos'), exe: '/Applications/freegosy.app/Contents/MacOS/freegosy').installKind,
          InstallKind.macApp);
      expect(svc(const PlatformInfo('macos'), exe: '/build/freegosy').installKind, InstallKind.manual);
    });
  });

  group('installer scripts', () {
    test('mac bundle path', () {
      expect(UpdateInstaller.macBundlePath('/Applications/freegosy.app/Contents/MacOS/freegosy'),
          '/Applications/freegosy.app');
    });
    test('mac script quotes paths and waits for the pid', () {
      final s = UpdateInstaller.macScript(pid: 42, zip: "/tmp/it's.zip", bundle: '/Applications/freegosy.app', workDir: '/tmp/w');
      expect(s, contains('kill -0 42'));
      expect(s, contains(r"'/tmp/it'\''s.zip'"));
    });
    test('windows portable script waits, extracts into the install dir, relaunches', () {
      final s = UpdateInstaller.windowsPortableScript(
          pid: 7, zip: r'C:\t\u.zip', installDir: r'C:\app', exe: r'C:\app\freegosy.exe');
      expect(s, contains('PID eq 7'));
      expect(s, contains("Expand-Archive -LiteralPath 'C:\\t\\u.zip' -DestinationPath 'C:\\app' -Force"));
      expect(s, contains(r'start "" "C:\app\freegosy.exe"'));
    });
    test('windows script runs silent installer then relaunches', () {
      final s = UpdateInstaller.windowsScript(setup: r'C:\t\setup.exe', exe: r'C:\app\freegosy.exe');
      expect(s, contains(r'"C:\t\setup.exe" /VERYSILENT'));
      expect(s, contains(r'start "" "C:\app\freegosy.exe"'));
    });
  });
}
