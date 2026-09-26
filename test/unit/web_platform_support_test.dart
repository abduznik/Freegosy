import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/app_path_resolver.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fails the test if the browser path ever asks for a disk location.
class _NoDiskPathResolver implements AppPathResolver {
  @override
  Future<String> getApplicationSupportPath() => throw StateError('web must not resolve app support path');

  @override
  Future<String> getTemporaryPath() => throw StateError('web must not resolve temp path');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('web must not resolve ${invocation.memberName}');
}

void main() {
  group('PlatformInfo.web', () {
    test('is web and none of the desktop platforms', () {
      const web = PlatformInfo.web;
      expect(web.isWeb, isTrue);
      expect(web.isWindows, isFalse);
      expect(web.isLinux, isFalse);
      expect(web.isMacOS, isFalse);
      expect(web.homeDir, isEmpty);
    });

    test('desktop platforms are not web', () {
      for (final os in ['windows', 'linux', 'macos']) {
        expect(PlatformInfo(os).isWeb, isFalse, reason: os);
      }
    });

    test('PlatformInfo.current reads dart:io off the web (tests run on the VM)', () {
      expect(PlatformInfo.current.isWeb, isFalse);
      expect(PlatformInfo.current.os, isNotEmpty);
    });
  });

  group('DirectoryService in a browser', () {
    late DirectoryService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'romsRootPath': '/should/not/be/used'});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      service = DirectoryService(prefs, platform: PlatformInfo.web, pathResolver: _NoDiskPathResolver());
    });

    test('initializes without touching the file system and reports no storage error', () async {
      final status = await service.initialize();
      expect(status.hasError, isFalse);
      expect(service.status.hasError, isFalse);
      expect(service.romsRootPath, isEmpty);
      expect(service.emulatorsRootPath, isEmpty);
    });

    test('never reports a game as downloaded', () async {
      await service.initialize();
      final game = Game(id: '1', name: 'Test Quest', platformSlug: 'snes', fileSize: 0);
      expect(await service.findExistingRomPath(game), isNull);
    });
  });
}
