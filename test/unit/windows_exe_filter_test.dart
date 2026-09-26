import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/windows/windows_game_service.dart';
import 'package:path/path.dart' as p;

/// WindowsGameService.shouldSkipExe() hides redistributables, installers and
/// anti-cheat helpers so exe auto-detection lands on the actual game
/// (issues #46 and #47: Freegosy kept asking for the executable).
void main() {
  group('WindowsGameService.shouldSkipExe', () {
    test('skips redistributables, installers and helper executables', () {
      const helpers = [
        'uninstall.exe', 'setup.exe', 'vc_redist.x64.exe',
        'vcredist_x86.exe', 'dxsetup.exe', 'directx_jun2010_redist.exe',
        'dotnetfx35.exe', 'crashreporter.exe', 'unitycrashhandler64.exe',
        'bugsplat64.exe', 'upc.exe', 'easyanticheat_setup.exe',
        'battleye_launcher.exe', 'launcher_helper.exe',
      ];
      for (final name in helpers) {
        expect(WindowsGameService.shouldSkipExe(name), isTrue, reason: name);
      }
    });

    test('keeps ordinary game executables', () {
      const games = ['hacknet.exe', 'fguy.exe', 'hollow knight.exe', 'celeste.exe', 'game.bat'];
      for (final name in games) {
        expect(WindowsGameService.shouldSkipExe(name), isFalse, reason: name);
      }
    });

    test('does not skip games whose names merely contain a blocked substring', () {
      // "upc" (Ubisoft Connect's upc.exe) is matched as a raw substring, so
      // any game with "upc" inside a word is hidden from exe detection.
      const games = ['cupcake.exe', 'soupcraft.exe', 'upcoming.exe'];
      for (final name in games) {
        expect(WindowsGameService.shouldSkipExe(name), isFalse, reason: name);
      }
    }, skip: 'Known bug: shouldSkipExe() matches blocklist entries as raw substrings. '
        'Remove skip once matching respects word boundaries.');

    test('skips Inno Setup uninstallers (unins000.exe)', () {
      // Inno Setup names its uninstaller unins000.exe, which contains neither
      // "uninstall" nor "uninst", so it slips through the blocklist.
      expect(WindowsGameService.shouldSkipExe('unins000.exe'), isTrue);
      expect(WindowsGameService.shouldSkipExe('unins001.exe'), isTrue);
    }, skip: 'Known bug: shouldSkipExe() does not match Inno Setup\'s unins000.exe. '
        'Remove skip once fixed.');
  });

  group('WindowsGameService.findExecutable skips helpers', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('windows_exe_filter_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('picks the game over a larger redistributable and uninstaller', () async {
      // Redistributables are often bigger than the game binary, so the
      // largest-exe fallback would choose them if they weren't filtered.
      await File(p.join(tempDir.path, 'Game.exe')).writeAsBytes(List.filled(10, 0));
      await File(p.join(tempDir.path, 'uninstall.exe')).writeAsBytes(List.filled(500, 0));
      await Directory(p.join(tempDir.path, '_CommonRedist')).create();
      await File(p.join(tempDir.path, '_CommonRedist', 'vc_redist.x64.exe')).writeAsBytes(List.filled(1000, 0));

      final exe = await WindowsGameService().findExecutable(tempDir.path);
      expect(exe, isNotNull);
      expect(p.basename(exe!), 'Game.exe');
    });

    test('picks the game over a larger Inno Setup unins000.exe', () async {
      await File(p.join(tempDir.path, 'Game.exe')).writeAsBytes(List.filled(10, 0));
      await File(p.join(tempDir.path, 'unins000.exe')).writeAsBytes(List.filled(500, 0));

      final exe = await WindowsGameService().findExecutable(tempDir.path);
      expect(p.basename(exe!), 'Game.exe');
    }, skip: 'Known bug: unins000.exe is not filtered and wins the largest-exe '
        'fallback. Remove skip once shouldSkipExe() handles it.');

    test('returns null when the folder only contains helpers', () async {
      await File(p.join(tempDir.path, 'setup.exe')).writeAsBytes(List.filled(10, 0));
      await File(p.join(tempDir.path, 'vcredist_x86.exe')).writeAsBytes(List.filled(10, 0));

      expect(await WindowsGameService().findExecutable(tempDir.path), isNull);
    });
  });
}
