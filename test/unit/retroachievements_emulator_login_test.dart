import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/strategies/retroarch_strategy.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/retroachievements/retroachievements_emulator_login.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../helpers/fake_retroachievements.dart';
import 'save_sync_regression_test.mocks.dart';

void main() {
  group('RetroAchievementsEmulatorLogin.load', () {
    setUp(useInMemorySecureStorage);
    tearDown(resetSecureStorage);

    test('is null without a username', () async {
      final prefs = InMemoryAppPreferences({secureKey(kRaConnectTokenSecureKey): 'tok'});
      expect(await RetroAchievementsEmulatorLogin.load(prefs), isNull);
    });

    test('is null when connected without a password (no token)', () async {
      final prefs = InMemoryAppPreferences({kRaUsernameKey: 'Player'});
      expect(await RetroAchievementsEmulatorLogin.load(prefs), isNull);
    });

    test('returns username, token and hardcore', () async {
      final prefs = InMemoryAppPreferences({
        kRaUsernameKey: 'Player',
        secureKey(kRaConnectTokenSecureKey): 'tok',
        kRaHardcoreKey: true,
      });
      final login = await RetroAchievementsEmulatorLogin.load(prefs);
      expect(login?.username, 'Player');
      expect(login?.token, 'tok');
      expect(login?.hardcore, isTrue);
    });

    test('hardcore defaults to off', () async {
      final prefs = InMemoryAppPreferences({kRaUsernameKey: 'P', secureKey(kRaConnectTokenSecureKey): 't'});
      expect((await RetroAchievementsEmulatorLogin.load(prefs))?.hardcore, isFalse);
    });
  });

  group('toRetroArchConfig', () {
    test('writes softcore config by default', () {
      final cfg = const RetroAchievementsEmulatorLogin(username: 'u', token: 't').toRetroArchConfig();
      expect(cfg, contains('cheevos_hardcore_mode_enable = "false"'));
      expect(cfg, endsWith('\n'));
    });

    test('strips quotes and line breaks so values cannot inject cfg lines', () {
      final cfg = const RetroAchievementsEmulatorLogin(username: 'a"b', token: 't"\r\ncheevos_x = "1')
          .toRetroArchConfig();
      expect(cfg, contains('cheevos_username = "ab"'));
      expect(cfg, contains('cheevos_token = "tcheevos_x = 1"'));
      expect(cfg.trim().split('\n'), hasLength(5));
    });
  });

  group('RetroArchStrategy.retroAchievementsLaunchArgs', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ra_cheevos_');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    RetroArchStrategy strategy(Future<RetroAchievementsEmulatorLogin?> Function() loader, {String os = 'linux'}) =>
        RetroArchStrategy(MockDirectoryService(), platform: PlatformInfo(os), raLoginLoader: loader);

    test('passes an --appendconfig file with the login when signed in', () async {
      final args = await strategy(() async => const RetroAchievementsEmulatorLogin(
            username: 'Player',
            token: 'tok',
            hardcore: true,
          )).retroAchievementsLaunchArgs();

      expect(args, hasLength(2));
      expect(args.first, '--appendconfig');
      final file = File(args.last);
      expect(file.parent.path, tempDir.path);
      final cfg = await file.readAsString();
      expect(cfg, contains('cheevos_enable = "true"'));
      expect(cfg, contains('cheevos_username = "Player"'));
      expect(cfg, contains('cheevos_token = "tok"'));
      expect(cfg, contains('cheevos_hardcore_mode_enable = "true"'));
    });

    test('keeps the token file private to the user', () async {
      final args = await strategy(() async => const RetroAchievementsEmulatorLogin(username: 'u', token: 't'))
          .retroAchievementsLaunchArgs();
      final mode = (await File(args.last).stat()).modeString();
      expect(mode, 'rw-------');
    }, skip: Platform.isWindows ? 'POSIX permissions only' : null);

    test('adds nothing when no emulator login is saved', () async {
      expect(await strategy(() async => null).retroAchievementsLaunchArgs(), isEmpty);
      expect(tempDir.listSync(), isEmpty);
    });

    test('never fails the launch if loading the login throws', () async {
      expect(await strategy(() async => throw StateError('keychain locked')).retroAchievementsLaunchArgs(), isEmpty);
    });

    test('overwrites the previous login on the next launch', () async {
      await strategy(() async => const RetroAchievementsEmulatorLogin(username: 'u', token: 'old'))
          .retroAchievementsLaunchArgs();
      final args = await strategy(() async => const RetroAchievementsEmulatorLogin(username: 'u', token: 'new'))
          .retroAchievementsLaunchArgs();
      final cfg = await File(args.last).readAsString();
      expect(cfg, contains('"new"'));
      expect(cfg, isNot(contains('"old"')));
    });

    test('RetroArch advertises RetroAchievements login support', () {
      expect(strategy(() async => null).supportsRetroAchievementsLogin, isTrue);
    });
  });
}

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String _path;
  _FakePathProvider(this._path);

  @override
  Future<String?> getApplicationSupportPath() async => _path;
}
