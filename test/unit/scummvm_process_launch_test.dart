import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/emulator/strategies/scummvm_strategy.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';

import 'strategy_registry_test.mocks.dart';

/// Launches ScummVMStrategy against a stand-in `scummvm` script that writes
/// the arguments and working directory it was started with, so the exact
/// command line is checked end to end through Process.start.
void main() {
  final canRunShellScripts = PlatformInfo.current.isLinux || PlatformInfo.current.isMacOS;
  late Directory tmp;
  late Directory gameDir;
  late File argsFile;
  late File cwdFile;
  late MockDirectoryService dirService;
  final game = Game(id: '7', name: 'Drascula', platformSlug: 'scummvm', fileSize: 0);

  Future<File> writeFakeScummVM(String name) async {
    final script = File(p.join(tmp.path, 'emu dir', name));
    await script.parent.create(recursive: true);
    await script.writeAsString('#!/bin/sh\n'
        'for a in "\$@"; do printf "%s\\n" "\$a"; done > "${argsFile.path}"\n'
        'pwd > "${cwdFile.path}"\n');
    await Process.run('chmod', ['+x', script.path]);
    return script;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('scummvm_launch');
    gameDir = Directory(p.join(tmp.path, 'games', 'Drascula The Vampire'));
    await gameDir.create(recursive: true);
    await File(p.join(gameDir.path, 'packet.001')).writeAsString('data');
    argsFile = File(p.join(tmp.path, 'args.txt'));
    cwdFile = File(p.join(tmp.path, 'cwd.txt'));
    dirService = MockDirectoryService();
  });

  tearDown(() => tmp.delete(recursive: true));

  List<String> recordedArgs() => argsFile.readAsLinesSync();

  test('passes --auto-detect and --path=<game folder>, with no trailing ROM argument', () async {
    final exe = await writeFakeScummVM('scummvm');
    when(dirService.findEmulatorExecutable('scummvm', any)).thenAnswer((_) async => exe.path);
    final strategy = ScummVMStrategy(dirService, platform: PlatformInfo.current);

    final process = await strategy.launchWithHandle(game, gameDir.path);

    expect(await process!.exitCode, 0);
    expect(recordedArgs(), ['--auto-detect', '--path=${gameDir.path}']);
  }, skip: !canRunShellScripts);

  test('a file picked inside the game folder still launches the folder', () async {
    final exe = await writeFakeScummVM('scummvm');
    when(dirService.findEmulatorExecutable('scummvm', any)).thenAnswer((_) async => exe.path);
    final strategy = ScummVMStrategy(dirService, platform: PlatformInfo.current);

    await strategy.launchWithHandle(game, p.join(gameDir.path, 'packet.001'));

    expect(recordedArgs(), ['--auto-detect', '--path=${gameDir.path}']);
  }, skip: !canRunShellScripts);

  test('runs from the emulator folder, even when its path has spaces', () async {
    final exe = await writeFakeScummVM('scummvm');
    when(dirService.findEmulatorExecutable('scummvm', any)).thenAnswer((_) async => exe.path);
    final strategy = ScummVMStrategy(dirService, platform: PlatformInfo.current);

    await strategy.launchWithHandle(game, gameDir.path);

    expect(p.canonicalize(cwdFile.readAsStringSync().trim()), p.canonicalize(exe.parent.path));
  }, skip: !canRunShellScripts);

  test('an EmuDeck-style .sh launcher is run through bash on Linux', () async {
    final exe = await writeFakeScummVM('scummvm.sh');
    await Process.run('chmod', ['-x', exe.path]); // bash runs it, it needn't be executable
    when(dirService.findEmulatorExecutable('scummvm', any)).thenAnswer((_) async => exe.path);
    final strategy = ScummVMStrategy(dirService, platform: const PlatformInfo('linux'));

    final process = await strategy.launchWithHandle(game, gameDir.path);

    expect(await process!.exitCode, 0);
    expect(recordedArgs(), ['--auto-detect', '--path=${gameDir.path}']);
  }, skip: !PlatformInfo.current.isLinux);

  test('the detached launch passes the same arguments', () async {
    final exe = await writeFakeScummVM('scummvm');
    when(dirService.findEmulatorExecutable('scummvm', any)).thenAnswer((_) async => exe.path);
    final strategy = ScummVMStrategy(dirService, platform: PlatformInfo.current);

    await strategy.launch(game, gameDir.path);
    for (var i = 0; i < 50 && !argsFile.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(recordedArgs(), ['--auto-detect', '--path=${gameDir.path}']);
  }, skip: !canRunShellScripts);

  test('throws a clear error when ScummVM is not installed', () async {
    when(dirService.findEmulatorExecutable('scummvm', any)).thenAnswer((_) async => null);
    // Windows: no distro-package fallback, so nothing is found.
    final strategy = ScummVMStrategy(dirService, platform: const PlatformInfo('windows'));

    expect(await strategy.findExecutable(), isNull);
    await expectLater(strategy.launchWithHandle(game, gameDir.path),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('ScummVM not found'))));
  });

  test('looks up the executable name for the current OS', () async {
    when(dirService.findEmulatorExecutable(any, any)).thenAnswer((_) async => null);
    for (final (os, name) in [('windows', 'scummvm.exe'), ('macos', 'ScummVM.app/Contents/MacOS/scummvm')]) {
      await ScummVMStrategy(dirService, platform: PlatformInfo(os)).findExecutable();
      verify(dirService.findEmulatorExecutable('scummvm', name)).called(1);
    }
  });
}
