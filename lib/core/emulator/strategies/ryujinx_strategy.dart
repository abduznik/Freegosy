import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import '../emulator_strategy.dart';

class RyujinxStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  RyujinxStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'Ryujinx';

  @override
  String get emulatorId => 'ryujinx';

  @override
  List<String> get supportedSlugs => ['switch', 'nintendo-switch', 'ns'];

  @override
  String get windowsExecutable => 'Ryujinx.exe';

  @override
  String get linuxExecutable => 'Ryujinx.AppImage';

  @override
  String get macosExecutable => 'Ryujinx.app/Contents/MacOS/Ryujinx';

  @override
  Future<String?> findExecutable() async {
    // 1. Try default discovery (direct path or override)
    final defaultExe = await super.findExecutable();
    if (defaultExe != null) return defaultExe;

    final emuDir = await _directoryService.getEmulatorDirectory(emulatorId);
    final dir = io.Directory(emuDir);
    if (!await dir.exists()) return null;

    // 2. Linux specific discovery
    if (io.Platform.isLinux) {
      await for (final entity in dir.list()) {
        if (entity is io.File) {
          final path = entity.path.toLowerCase();
          if (path.contains('ryujinx') && path.endsWith('.appimage')) {
            return entity.path;
          }
        }
      }
    }

    // 3. macOS specific discovery (.app bundle)
    if (io.Platform.isMacOS) {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is io.Directory && p.basename(entity.path) == 'Ryujinx.app') {
          final binary = io.File(p.join(entity.path, 'Contents', 'MacOS', 'Ryujinx'));
          if (await binary.exists()) return binary.path;
        }
      }
    }

    // 4. Windows Recursive Discovery (Required for publish/ folder)
    if (io.Platform.isWindows) {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is io.File) {
          if (p.basename(entity.path).toLowerCase() == 'ryujinx.exe') {
            return entity.path;
          }
        }
      }
    }

    return null;
  }

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    debugPrint('[Ryujinx] Strategy Received romPath: $romPath');

    if (io.Platform.isWindows) {
      debugPrint('[Ryujinx] Delegating to DirectoryService for Windows launch');
      await _directoryService.launchGame(game, romPath, emulatorId, exePath);
      return;
    }

    final absRomPath = io.File(romPath).absolute.path;

    // Auto-fix permissions on macOS/Linux
    if (io.Platform.isMacOS || io.Platform.isLinux) {
      await io.Process.run('chmod', ['+x', exePath]);
      if (io.Platform.isMacOS) {
        await _ensureEntitlements(exePath);
        final exeDir = io.File(exePath).parent.path;
        await io.Process.start(
          exePath,
          [absRomPath],
          mode: io.ProcessStartMode.detached,
          workingDirectory: exeDir,
        );
        return;
      }
    }

    await super.launch(game, absRomPath);
  }

  @override
  Future<io.Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    debugPrint('[Ryujinx] Strategy Received romPath (with handle): $romPath');

    if (io.Platform.isWindows) {
      debugPrint('[Ryujinx] Delegating to DirectoryService for Windows handle launch');
      return await _directoryService.launchGameWithHandle(game, romPath, emulatorId, exePath);
    }

    final absRomPath = io.File(romPath).absolute.path;

    // macOS/Linux permission handling
    if (io.Platform.isMacOS || io.Platform.isLinux) {
      await io.Process.run('chmod', ['+x', exePath]);
      if (io.Platform.isMacOS) await _ensureEntitlements(exePath);
    }

    if (io.Platform.isMacOS) {
      final exeDir = io.File(exePath).parent.path;
      final process = await io.Process.start(
        exePath,
        [absRomPath],
        mode: io.ProcessStartMode.normal,
        workingDirectory: exeDir,
      );
      // macOS requires draining buffers to prevent process hang
      process.stdout.listen((_) {});
      process.stderr.listen((_) {});
      return process;
    }

    return await super.launchWithHandle(game, absRomPath);
  }

  @override
  Future<void> launchStandalone() async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    if (io.Platform.isWindows) {
      final exeDir = io.File(exePath).parent.path;
      debugPrint('[Ryujinx] Launching Windows Standalone (No ROM)');
      debugPrint('[Ryujinx] Executable: $exePath');
      debugPrint('[Ryujinx] Working Directory: $exeDir');
      
      try {
        final process = await io.Process.start(
          exePath,
          [],
          mode: io.ProcessStartMode.detached,
          workingDirectory: exeDir,
          runInShell: true,
          includeParentEnvironment: true,
        );
        debugPrint('[Ryujinx] Standalone process started with PID: ${process.pid}');
      } catch (e) {
        if (e is io.ProcessException) {
          debugPrint('[Ryujinx] Standalone ProcessException: ${e.message} (Exit Code: ${e.errorCode})');
        }
        debugPrint('[Ryujinx] Failed to start standalone process: $e');
        rethrow;
      }
      return;
    }

    await super.launchStandalone();
  }

  Future<void> _ensureEntitlements(String exePath) async {
    if (!io.Platform.isMacOS) return;
    final appPath = exePath.split('/Contents/MacOS/').first;
    final checkResult = await io.Process.run('codesign', ['-dv', '--entitlements', '-', appPath]);
    if (checkResult.stderr.toString().contains('com.apple.security.hypervisor') || 
        checkResult.stdout.toString().contains('com.apple.security.hypervisor')) {
      return;
    }

    debugPrint('[Ryujinx] Hypervisor entitlement missing. Re-signing...');
    final entitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key><true/>
    <key>com.apple.security.cs.allow-jit</key><true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
    <key>com.apple.security.cs.debugger</key><true/>
    <key>com.apple.security.cs.disable-executable-page-protection</key><true/>
    <key>com.apple.security.cs.disable-library-validation</key><true/>
    <key>com.apple.security.get-task-allow</key><true/>
    <key>com.apple.security.hypervisor</key><true/>
</dict>
</plist>
''';

    final tempFile = io.File('${io.Directory.systemTemp.path}/ryujinx_entitlements.plist');
    await tempFile.writeAsString(entitlements);
    try {
      await io.Process.run('codesign', [
        '--sign', '-', '--force', '--deep', '--entitlements', tempFile.path, appPath,
      ]);
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  @override
  bool get supportsSaveSync => true;

  @override
  String resolveSavePath(Game game) => "";
}
