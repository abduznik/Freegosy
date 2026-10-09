import 'dart:io' as io;

import 'package:path/path.dart' as p;

import 'update_models.dart';

/// Swaps a downloaded update in for the running app and relaunches it.
/// Each platform has a different story, so the work is a small helper script
/// where the running process can't replace itself.
class UpdateInstaller {
  final Map<String, String> environment;
  final String resolvedExecutable;
  final int pid;

  /// Starts a process that outlives this one. Injectable for tests.
  final Future<void> Function(String exe, List<String> args) _spawnDetached;

  UpdateInstaller({
    Map<String, String>? environment,
    String? resolvedExecutable,
    int? pid,
    Future<void> Function(String exe, List<String> args)? spawnDetached,
  })  : environment = environment ?? io.Platform.environment,
        resolvedExecutable = resolvedExecutable ?? io.Platform.resolvedExecutable,
        pid = pid ?? io.pid,
        _spawnDetached = spawnDetached ?? _defaultSpawn;

  static Future<void> _defaultSpawn(String exe, List<String> args) async {
    await io.Process.start(exe, args, mode: io.ProcessStartMode.detached);
  }

  /// Installs [file] and launches the new version. The caller must exit the
  /// app right after this returns.
  Future<void> installAndRestart(InstallKind kind, io.File file) async {
    switch (kind) {
      case InstallKind.appImage:
        return _appImage(file);
      case InstallKind.windowsInstaller:
        return _windows(file);
      case InstallKind.windowsPortable:
        return _windowsPortable(file);
      case InstallKind.macApp:
        return _mac(file);
      case InstallKind.manual:
        throw StateError('This install type cannot update itself');
    }
  }

  Future<void> _appImage(io.File file) async {
    final target = environment['APPIMAGE'];
    if (target == null || target.isEmpty) throw StateError('APPIMAGE is not set');
    // Same directory, so the final rename is atomic; replacing a running
    // AppImage this way is safe, the old process keeps its open inode.
    final staged = '$target.update';
    await file.copy(staged);
    final chmod = await io.Process.run('chmod', ['755', staged]);
    if (chmod.exitCode != 0) throw StateError('Could not make the update executable: ${chmod.stderr}');
    await io.File(staged).rename(target);
    await _spawnDetached('sh', ['-c', 'sleep 1; exec "\$0"', target]);
  }

  Future<void> _windows(io.File file) async {
    final bat = io.File(p.join(file.parent.path, 'apply_update.bat'));
    await bat.writeAsString(windowsScript(setup: file.path, exe: resolvedExecutable));
    await _spawnDetached('cmd', ['/c', bat.path]);
  }

  Future<void> _windowsPortable(io.File file) async {
    final bat = io.File(p.join(file.parent.path, 'apply_update.bat'));
    await bat.writeAsString(windowsPortableScript(
        pid: pid, zip: file.path, installDir: p.dirname(resolvedExecutable), exe: resolvedExecutable));
    await _spawnDetached('cmd', ['/c', bat.path]);
  }

  Future<void> _mac(io.File file) async {
    final bundle = macBundlePath(resolvedExecutable);
    final script = io.File(p.join(file.parent.path, 'apply_update.sh'));
    await script.writeAsString(macScript(pid: pid, zip: file.path, bundle: bundle, workDir: file.parent.path));
    await _spawnDetached('sh', [script.path]);
  }

  /// `/Applications/freegosy.app/Contents/MacOS/freegosy` → `/Applications/freegosy.app`.
  static String macBundlePath(String exe) => p.dirname(p.dirname(p.dirname(exe)));

  static String windowsScript({required String setup, required String exe}) {
    String q(String s) => '"${s.replaceAll('%', '%%')}"';
    return '@echo off\r\n'
        'ping -n 3 127.0.0.1 >nul\r\n'
        '${q(setup)} /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS\r\n'
        'start "" ${q(exe)}\r\n';
  }

  /// Waits for [pid] to exit (so no file is locked), extracts the zip over
  /// [installDir], then relaunches.
  static String windowsPortableScript({required int pid, required String zip, required String installDir, required String exe}) {
    String q(String s) => '"${s.replaceAll('%', '%%')}"';
    String ps(String s) => "'${s.replaceAll("'", "''")}'";
    return '@echo off\r\n'
        ':wait\r\n'
        'tasklist /FI "PID eq $pid" 2>nul | find "$pid" >nul\r\n'
        'if not errorlevel 1 (\r\n'
        '  ping -n 2 127.0.0.1 >nul\r\n'
        '  goto wait\r\n'
        ')\r\n'
        'powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath ${ps(zip).replaceAll('"', '\\"')} -DestinationPath ${ps(installDir).replaceAll('"', '\\"')} -Force"\r\n'
        'start "" ${q(exe)}\r\n';
  }

  static String macScript({required int pid, required String zip, required String bundle, required String workDir}) {
    String q(String s) => "'${s.replaceAll("'", r"'\''")}'";
    final staging = '$workDir/extracted';
    return '#!/bin/sh\n'
        'while kill -0 $pid 2>/dev/null; do sleep 0.5; done\n'
        'rm -rf ${q(staging)} && mkdir -p ${q(staging)} || exit 1\n'
        'ditto -x -k ${q(zip)} ${q(staging)} || exit 1\n'
        'NEW=\$(find ${q(staging)} -maxdepth 1 -name "*.app" | head -n 1)\n'
        '[ -n "\$NEW" ] || exit 1\n'
        'rm -rf ${q(bundle)} && mv "\$NEW" ${q(bundle)} || exit 1\n'
        'xattr -dr com.apple.quarantine ${q(bundle)} 2>/dev/null\n'
        'open ${q(bundle)}\n';
  }
}
