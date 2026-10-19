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
    test('build metadata is ignored; numeric suffix parts compare as numbers', () {
      expect(VersionCompare.compare('0.6.1+1', '0.6.1'), 0);
      expect(VersionCompare.isNewer('0.6.2-pre.10', '0.6.2-pre.9'), isTrue);
    });
    test('garbage never counts as newer', () {
      expect(VersionCompare.isNewer('nightly', '0.6.1'), isFalse);
    });
  });

  group('nightly', () {
    // The rolling nightly: tag `nightly`, notes name the release it is based on.
    Map<String, dynamic> nightly({String base = '0.6.1', String sha = 'abc', String published = '2026-10-14T10:00:00Z'}) => {
          ...release('nightly', pre: true, assets: ['Freegosy-linux-x86_64.AppImage']),
          'body': 'Nightly build of commit 1234567. Based on version $base.',
          'published_at': published,
          'assets': [
            {'name': 'Freegosy-linux-x86_64.AppImage', 'browser_download_url': 'https://x/nightly/a', 'size': 10, 'digest': 'sha256:$sha'},
          ],
        };
    final pre061 = release('v0.6.1', pre: true, assets: ['Freegosy-linux-x86_64.AppImage']); // digest abc

    UpdateInfo? pick(List<dynamic> r, String current, UpdateChannel c, {String? installed, bool running = false}) =>
        UpdateService.pickUpdate(r, current, c, InstallKind.appImage, installedSha: installed, runningNightly: running);

    test('stable and pre-release channels never see it', () {
      expect(pick([nightly()], '0.6.0', UpdateChannel.stable), isNull);
      expect(pick([nightly()], '0.6.0', UpdateChannel.prerelease), isNull);
    });

    test('nightly channel offers it when the digest differs, or is unknown', () {
      final u = pick([nightly()], '0.6.1', UpdateChannel.nightly, installed: 'old')!;
      expect(u.tag, 'nightly');
      expect(u.isNightly, isTrue);
      expect(u.version, '0.6.1'); // what the build will report, so a recorded install matches it
      expect(u.sha256, 'abc');
      expect(pick([nightly()], '0.6.1', UpdateChannel.nightly), isNotNull);
    });

    test('nothing more to do once this exact nightly is installed; the next night is offered', () {
      expect(pick([nightly()], '0.6.1', UpdateChannel.nightly, installed: 'abc', running: true), isNull);
      expect(pick([nightly(sha: 'def')], '0.6.1', UpdateChannel.nightly, installed: 'abc', running: true)!.sha256, 'def');
    });

    test('a nightly build is not offered the release it was built after (the stuck "0.6.1 is available")', () {
      // Running a nightly that reports 0.6.1; the v0.6.1 pre-release has a different digest.
      for (final c in UpdateChannel.values) {
        expect(pick([pre061], '0.6.1', c, installed: 'mine', running: true), isNull, reason: '$c');
      }
      // Without the nightly flag the same situation is a genuine same-version rebuild.
      expect(pick([pre061], '0.6.1', UpdateChannel.prerelease, installed: 'mine')?.isRebuild, isTrue);
    });

    test('on the nightly channel only the nightly is offered, not v0.6.1', () {
      final u = pick([pre061, nightly(sha: 'def')], '0.6.1', UpdateChannel.nightly, installed: 'abc', running: true)!;
      expect(u.tag, 'nightly');
    });

    test('a newer real release is offered to a nightly build, and wins over the nightly', () {
      final r = [release('v0.6.2', assets: ['Freegosy-linux-x86_64.AppImage']), nightly()];
      expect(pick(r, '0.6.1', UpdateChannel.stable, installed: 'abc', running: true)!.tag, 'v0.6.2');
      expect(pick(r, '0.6.1', UpdateChannel.nightly, installed: 'old', running: true)!.tag, 'v0.6.2');
    });

    test('a nightly based on an older release than the running build is no update', () {
      expect(pick([nightly(base: '0.6.1')], '0.6.2', UpdateChannel.nightly, installed: 'old'), isNull);
    });

    test('with several nightly releases the newest is used', () {
      final old = nightly(sha: 'old1', published: '2026-10-10T00:00:00Z');
      final newer = nightly(sha: 'new1', published: '2026-10-14T00:00:00Z');
      expect(pick([old, newer], '0.6.1', UpdateChannel.nightly, installed: 'x')!.sha256, 'new1');
      expect(pick([newer, old], '0.6.1', UpdateChannel.nightly, installed: 'x')!.sha256, 'new1');
    });

    test('base version is read from the notes', () {
      expect(UpdateService.nightlyBaseVersion('Nightly build of commit abc. Based on version 0.6.1.'), '0.6.1');
      expect(UpdateService.nightlyBaseVersion('based on version v1.2.3'), '1.2.3');
      expect(UpdateService.nightlyBaseVersion('no version here'), isNull);
      expect(UpdateService.nightlyBaseVersion(null), isNull);
    });

    test('tags: nightly, and the older v<version>-nightly', () {
      expect(UpdateService.isNightlyTag('nightly'), isTrue);
      expect(UpdateService.isNightlyTag('v0.6.1-nightly'), isTrue);
      expect(UpdateService.isNightlyTag('v0.6.1'), isFalse);
      expect(UpdateService.isNightlyTag(null), isFalse);
    });

    test('channel setting parses', () {
      expect(UpdateChannel.parse('nightly'), UpdateChannel.nightly);
      expect(UpdateChannel.parse('prerelease'), UpdateChannel.prerelease);
      expect(UpdateChannel.parse(null), UpdateChannel.stable);
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
