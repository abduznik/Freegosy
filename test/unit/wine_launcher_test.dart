import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/windows/wine_launcher.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory bin;

  setUp(() => bin = Directory.systemTemp.createTempSync('wine_bin'));
  tearDown(() => bin.deleteSync(recursive: true));

  void install(String name) => File(p.join(bin.path, name)).writeAsStringSync('#!/bin/sh\n');

  test('only Windows programs need Wine', () {
    expect(WineLauncher.needsWine('/g/Game.EXE'), isTrue);
    expect(WineLauncher.needsWine('/g/run.bat'), isTrue);
    expect(WineLauncher.needsWine('/g/start.sh'), isFalse);
    expect(WineLauncher.needsWine('/g/Game.AppImage'), isFalse);
  });

  test('umu-run (Proton) is preferred and gets its own prefix and GE-Proton', () {
    install('wine');
    install('umu-run');
    final c = WineLauncher.build(exePath: '/g/Game.exe', args: ['-windowed'], prefixDir: '/pfx/7', dirs: [bin.path])!;
    expect(c.runner, 'umu-run');
    expect(c.executable, p.join(bin.path, 'umu-run'));
    expect(c.args, ['/g/Game.exe', '-windowed']);
    expect(c.environment['WINEPREFIX'], '/pfx/7');
    expect(c.environment['PROTONPATH'], 'GE-Proton');
    expect(c.environment['GAMEID'], 'umu-0');
  });

  test('falls back to wine, and the preference can force either runner', () {
    install('wine');
    final c = WineLauncher.build(exePath: '/g/a.exe', args: [], prefixDir: '/pfx/1', dirs: [bin.path])!;
    expect(c.runner, 'wine');
    expect(c.environment.containsKey('PROTONPATH'), isFalse);
    install('umu-run');
    expect(WineLauncher.build(exePath: '/g/a.exe', args: [], prefixDir: '/p', preference: 'wine', dirs: [bin.path])!.runner, 'wine');
    expect(WineLauncher.build(exePath: '/g/a.exe', args: [], prefixDir: '/p', preference: 'umu', dirs: [bin.path])!.runner, 'umu-run');
  });

  test('nothing installed means no command', () {
    expect(WineLauncher.build(exePath: '/g/a.exe', args: [], prefixDir: '/p', dirs: [bin.path]), isNull);
    install('wine');
    expect(WineLauncher.build(exePath: '/g/a.exe', args: [], prefixDir: '/p', preference: 'umu', dirs: [bin.path]), isNull);
  });

  test('finds programs on PATH and in the standard folders when PATH is bare', () {
    install('umu-run');
    expect(WineLauncher.find('umu-run', environment: {'PATH': bin.path}), p.join(bin.path, 'umu-run'));
    // A gamescope/AppImage session without /usr/bin on PATH still finds system programs.
    expect(WineLauncher.find('sh', environment: {'PATH': ''}), isNotNull);
  });

  group('findInstalledProton', () {
    late Directory steam;
    setUp(() => steam = Directory.systemTemp.createTempSync('steam_root'));
    tearDown(() => steam.deleteSync(recursive: true));

    void proton(String relative) {
      Directory(p.join(steam.path, relative)).createSync(recursive: true);
      File(p.join(steam.path, relative, 'proton')).writeAsStringSync('');
    }

    String? find() => WineLauncher.findInstalledProton(steamRoots: [steam.path]);

    test('nothing installed means null, so umu downloads GE-Proton', () => expect(find(), isNull));

    test('a custom GE-Proton beats Steam\'s own, newest first', () {
      proton('steamapps/common/Proton 9.0');
      proton('compatibilitytools.d/GE-Proton9-5');
      proton('compatibilitytools.d/GE-Proton10-2');
      expect(p.basename(find()!), 'GE-Proton10-2');
    });

    test('Steam\'s numbered versions come before Proton - Experimental, newest first', () {
      proton('steamapps/common/Proton - Experimental');
      proton('steamapps/common/Proton 8.0');
      proton('steamapps/common/Proton 9.0');
      expect(p.basename(find()!), 'Proton 9.0');
    });

    test('Experimental alone is used, and folders without the proton script are ignored', () {
      Directory(p.join(steam.path, 'steamapps/common/Proton 10.0')).createSync(recursive: true); // no script
      proton('steamapps/common/Proton - Experimental');
      expect(p.basename(find()!), 'Proton - Experimental');
    });

    test('the found Proton goes into PROTONPATH unless the environment sets one', () {
      File(p.join(bin.path, 'umu-run')).writeAsStringSync('#!/bin/sh\n');
      final c = WineLauncher.build(exePath: '/g/a.exe', args: [], prefixDir: '/p', dirs: [bin.path], protonPath: '/steam/Proton 9.0')!;
      expect(c.environment['PROTONPATH'], '/steam/Proton 9.0');
      final own = WineLauncher.build(
          exePath: '/g/a.exe', args: [], prefixDir: '/p', dirs: [bin.path], protonPath: '/steam/Proton 9.0', environment: {'PROTONPATH': '/mine'})!;
      expect(own.environment['PROTONPATH'], '/mine');
    });
  });
}
