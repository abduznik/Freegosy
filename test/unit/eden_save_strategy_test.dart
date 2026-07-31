import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/eden_save_strategy.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal DirectoryService stub — only implements the two methods
/// EdenSaveStrategy calls during save resolution.
class _StubDirectoryService extends DirectoryService {
  final String? _exePath;
  final String _appSupport;

  _StubDirectoryService._internal(
    super.prefs, {
    required String? exePath,
    required String appSupport,
  })  : _exePath = exePath,
        _appSupport = appSupport;

  static Future<_StubDirectoryService> create({
    String? exePath,
    String appSupport = '',
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return _StubDirectoryService._internal(prefs, exePath: exePath, appSupport: appSupport);
  }

  @override
  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async => _exePath;

  @override
  Future<String> getEmulatorAppSupportDirectory(String emulatorName, {String? platformSlug}) async => _appSupport;
}

/// Creates the nand save folder structure Eden expects:
///   `<base>/nand/user/save/0000000000000000/<profileId>/<titleId>/data.bin`
Future<void> _createSaveStructure(String base, String profileId, String titleId) async {
  final dir = p.join(base, 'nand', 'user', 'save', '0000000000000000', profileId, titleId);
  await Directory(dir).create(recursive: true);
  await File(p.join(dir, 'data.bin')).writeAsBytes([0, 1, 2]);
}

void main() {
  group('EdenSaveStrategy portable mode detection', () {
    test('uses portable save path when user/ folder exists next to exe', () async {
      final tempDir = await Directory.systemTemp.createTemp('eden_portable_test');
      try {
        final exeDir = tempDir.path;
        final portableBase = p.join(exeDir, 'user');
        await _createSaveStructure(portableBase, 'a' * 32, '0100000000000000');

        final fakeExe = p.join(exeDir, 'eden.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = EdenSaveStrategy(
          ds,
          platform: const PlatformInfo('windows', environment: {'APPDATA': ''}),
        );

        final saveDir = await strategy.getSaveDir(
          Game(id: 'g1', name: 'Test Game', platformSlug: 'switch', fileSize: 0),
          p.join(exeDir, '0100000000000000.nsp'),
        );

        expect(saveDir, isNotNull);
        expect(p.isWithin(portableBase, saveDir!), isTrue,
            reason: 'Expected save inside portable user/ folder');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('falls back to APPDATA when no portable user/ folder exists', () async {
      final tempDir = await Directory.systemTemp.createTemp('eden_appdata_test');
      final exeTempDir = await Directory.systemTemp.createTemp('eden_exe_dir');
      try {
        final appdataEden = p.join(tempDir.path, 'eden');
        await _createSaveStructure(appdataEden, 'b' * 32, '0100000000010000');

        // exe exists but has no user/ folder beside it
        final fakeExe = p.join(exeTempDir.path, 'eden.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(
          exePath: fakeExe,
          appSupport: appdataEden,
        );
        final strategy = EdenSaveStrategy(
          ds,
          platform: PlatformInfo('windows', environment: {'APPDATA': tempDir.path}),
        );

        final saveDir = await strategy.getSaveDir(
          Game(id: 'g2', name: 'Test Game 2', platformSlug: 'switch', fileSize: 0),
          p.join(tempDir.path, '0100000000010000.nsp'),
        );

        expect(saveDir, isNotNull);
        expect(p.isWithin(appdataEden, saveDir!), isTrue,
            reason: 'Expected save inside APPDATA eden/ folder');
      } finally {
        await tempDir.delete(recursive: true);
        await exeTempDir.delete(recursive: true);
      }
    });
  });

  group('EdenSaveStrategy username special characters', () {
    // Regression for issue #68: portable Eden users couldn't sync saves.
    // Also validates that paths with spaces or non-ASCII characters in the
    // username segment do not prevent the strategy from resolving directories.

    test('resolves portable save path when exe dir contains spaces in username', () async {
      final base = await Directory.systemTemp.createTemp('eden_space_portable');
      try {
        final exeDir = Directory(p.join(base.path, 'John Doe', 'eden'));
        await exeDir.create(recursive: true);

        final portableBase = p.join(exeDir.path, 'user');
        await _createSaveStructure(portableBase, 'c' * 32, '0100000000020000');

        final fakeExe = p.join(exeDir.path, 'eden.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = EdenSaveStrategy(
          ds,
          platform: const PlatformInfo('windows', environment: {'APPDATA': ''}),
        );

        final saveDir = await strategy.getSaveDir(
          Game(id: 'g3', name: 'Spaced Game', platformSlug: 'switch', fileSize: 0),
          p.join(exeDir.path, '0100000000020000.nsp'),
        );

        expect(saveDir, isNotNull);
        expect(saveDir, contains('John Doe'));
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('resolves APPDATA save path when username contains spaces', () async {
      final base = await Directory.systemTemp.createTemp('eden_appdata_space');
      try {
        final appdata = p.join(base.path, 'Jane Smith', 'AppData', 'Roaming');
        final appdataEden = p.join(appdata, 'eden');
        await _createSaveStructure(appdataEden, 'd' * 32, '0100000000030000');

        final ds = await _StubDirectoryService.create(
          exePath: null, // no exe → skip portable check
          appSupport: appdataEden,
        );
        final strategy = EdenSaveStrategy(
          ds,
          platform: PlatformInfo('windows', environment: {'APPDATA': appdata}),
        );

        final saveDir = await strategy.getSaveDir(
          Game(id: 'g4', name: 'Space User Game', platformSlug: 'switch', fileSize: 0),
          p.join(base.path, '0100000000030000.nsp'),
        );

        expect(saveDir, isNotNull);
        expect(saveDir, contains('Jane Smith'));
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('resolves portable save path when exe dir contains non-ASCII characters', () async {
      final base = await Directory.systemTemp.createTemp('eden_unicode_portable');
      try {
        final exeDir = Directory(p.join(base.path, 'Ångström', 'eden'));
        await exeDir.create(recursive: true);

        final portableBase = p.join(exeDir.path, 'user');
        await _createSaveStructure(portableBase, 'e' * 32, '0100000000040000');

        final fakeExe = p.join(exeDir.path, 'eden.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = EdenSaveStrategy(
          ds,
          platform: const PlatformInfo('windows', environment: {'APPDATA': ''}),
        );

        final saveDir = await strategy.getSaveDir(
          Game(id: 'g5', name: 'Unicode Game', platformSlug: 'switch', fileSize: 0),
          p.join(exeDir.path, '0100000000040000.nsp'),
        );

        expect(saveDir, isNotNull);
        expect(saveDir, contains('Ångström'));
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('resolves APPDATA save path when username contains non-ASCII characters', () async {
      final base = await Directory.systemTemp.createTemp('eden_appdata_unicode');
      try {
        final appdata = p.join(base.path, 'Ñoño', 'AppData', 'Roaming');
        final appdataEden = p.join(appdata, 'eden');
        await _createSaveStructure(appdataEden, 'f' * 32, '0100000000050000');

        final ds = await _StubDirectoryService.create(
          exePath: null,
          appSupport: appdataEden,
        );
        final strategy = EdenSaveStrategy(
          ds,
          platform: PlatformInfo('windows', environment: {'APPDATA': appdata}),
        );

        final saveDir = await strategy.getSaveDir(
          Game(id: 'g6', name: 'Unicode User Game', platformSlug: 'switch', fileSize: 0),
          p.join(base.path, '0100000000050000.nsp'),
        );

        expect(saveDir, isNotNull);
        expect(saveDir, contains('Ñoño'));
      } finally {
        await base.delete(recursive: true);
      }
    });
  });
}
