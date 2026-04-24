import 'dart:io' as io;
import 'package:flutter/foundation.dart';
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
    final defaultExe = await super.findExecutable();
    if (defaultExe != null) return defaultExe;

    final emuDir = await _directoryService.getEmulatorDirectory(emulatorId);
    final dir = io.Directory(emuDir);
    if (!await dir.exists()) return null;

    // Search for any file containing 'ryujinx' and ending in '.appimage' on Linux
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

    // Search for .app bundle on macOS if default path failed
    if (io.Platform.isMacOS) {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is io.Directory && entity.path.contains('Ryujinx.app')) {
          final binary = io.File('${entity.path}/Contents/MacOS/Ryujinx');
          if (await binary.exists()) return binary.path;
        }
      }
    }

    return null;
  }

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    final absRomPath = io.File(romPath).absolute.path;

    // Auto-fix permissions on macOS/Linux before launching
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

    // Windows/Linux use standard launch
    await super.launch(game, absRomPath);
  }

  @override
  Future<io.Process?> launchWithHandle(Game game, String romPath) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    final absRomPath = io.File(romPath).absolute.path;

    // Auto-fix permissions
    if (io.Platform.isMacOS || io.Platform.isLinux) {
      await io.Process.run('chmod', ['+x', exePath]);
      if (io.Platform.isMacOS) {
        await _ensureEntitlements(exePath);
      }
    }

    if (io.Platform.isMacOS) {
      final exeDir = io.File(exePath).parent.path;
      final process = await io.Process.start(
        exePath,
        [absRomPath],
        mode: io.ProcessStartMode.normal,
        workingDirectory: exeDir,
      );

      // Drain buffers to prevent hang
      process.stdout.listen((_) {});
      process.stderr.listen((_) {});

      return process;
    } else {
      return await super.launchWithHandle(game, absRomPath);
    }
  }

  Future<void> _ensureEntitlements(String exePath) async {
    if (!io.Platform.isMacOS) return;

    final appPath = exePath.split('/Contents/MacOS/').first;
    
    // Check if entitlements already contain hypervisor
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
      final signResult = await io.Process.run('codesign', [
        '--sign', '-',
        '--force',
        '--deep',
        '--entitlements', tempFile.path,
        appPath,
      ]);

      debugPrint('[Ryujinx] codesign exit: ${signResult.exitCode}');
      if (signResult.exitCode != 0) {
        debugPrint('[Ryujinx] codesign stderr: ${signResult.stderr}');
      }
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  @override
  bool get supportsSaveSync => true;

  @override
  String resolveSavePath(Game game) {
    return "";
  }
}
