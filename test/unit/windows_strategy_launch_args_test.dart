import 'dart:convert';
import 'dart:io';
import 'dart:io' as io;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/emulator/strategies/windows_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';

/// Regression coverage for issue #47: WindowsStrategy.launchWithHandle()
/// previously delegated to DirectoryService.launchGameWithHandle(), which
/// appends `romPath` after the configured launch args for every emulator
/// strategy (correct for a real emulator that expects a ROM file argument,
/// wrong for a native .exe with its own complete argument list). This broke
/// shared multi-game launchers like OpenGOAL's "gk.exe --game jak1", which
/// received an unexpected trailing game-folder path argument.
///
/// Verified against a real process (cmd.exe /c echo, always present on
/// Windows) rather than mocking Process.start, since the bug is
/// specifically about what argument list actually reaches the child
/// process.
void main() {
  test('launchWithHandle passes exactly the configured args, without appending romPath', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final dirService = DirectoryService(prefs);
    final strategy = WindowsStrategy(dirService, prefs);

    final game = Game(id: 'test1', name: 'Test Game', fileSize: 0, platformSlug: 'windows');

    final tempDir = await Directory.systemTemp.createTemp('windows_launch_args_test');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    // A small PowerShell script that writes each argument it receives (via
    // $args), one per line, to a file — avoids cmd.exe's nested-quoting
    // pitfalls and gives an exact, unambiguous view of argv. launchWithHandle
    // drains stdout internally (to avoid pipe-buffer deadlock), so output
    // is captured via file write rather than reading the process's stdout.
    final outFile = File('${tempDir.path}\\args_seen.txt');
    final dumpArgsPs1 = File('${tempDir.path}\\dump_args.ps1');
    await dumpArgsPs1.writeAsString(r'$args | Out-File -Encoding utf8 -FilePath "' + outFile.path + r'"');

    final systemRoot = io.Platform.environment['SystemRoot'] ?? 'C:\\Windows';
    final powershellExe = '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
    await strategy.setExeOverride(game.id, powershellExe);
    await strategy.setLaunchArgs(game.id, [
      '-NoProfile',
      '-File',
      dumpArgsPs1.path,
      '--game',
      'jak1',
    ]);

    final romPath = '${tempDir.path}\\Test Game'; // a folder path, as WindowsStrategy expects

    final process = await strategy.launchWithHandle(game, romPath);
    expect(process, isNotNull);
    final exitCode = await process!.exitCode;
    await Future.delayed(const Duration(milliseconds: 300));

    expect(await outFile.exists(), isTrue,
        reason: 'powershell.exe should have run dump_args.ps1 and produced output (exit code: $exitCode)');
    // Out-File -Encoding utf8 on Windows PowerShell 5.1 writes a UTF-8 BOM;
    // strip it before splitting into lines.
    final rawBytes = await outFile.readAsBytes();
    final withoutBom = (rawBytes.length >= 3 && rawBytes[0] == 0xEF && rawBytes[1] == 0xBB && rawBytes[2] == 0xBF)
        ? rawBytes.sublist(3)
        : rawBytes;
    final content = utf8.decode(withoutBom);
    final seenArgs = content.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // If romPath had been appended as an extra argv entry (the bug), it
    // would show up as a third line in $args here.
    expect(seenArgs, ['--game', 'jak1'],
        reason: 'launchWithHandle must pass exactly the configured launch args — '
            'romPath must NOT be appended as an extra trailing argument. Got: $seenArgs');
  }, testOn: 'windows');
}
