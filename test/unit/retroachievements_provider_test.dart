import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/retroachievements/retroachievements_emulator_login.dart';
import 'package:freegosy/core/retroachievements/retroachievements_models.dart';
import 'package:freegosy/providers/retroachievements_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';

import '../helpers/fake_retroachievements.dart';

/// Covers the Settings connect/disconnect rules: username required, password
/// and Web API key each optional (but not both missing), the password turned
/// into an emulator token and never stored.
void main() {
  late InMemoryAppPreferences prefs;
  late FakeRetroAchievementsService service;
  late ProviderContainer container;

  setUp(() {
    useInMemorySecureStorage();
    prefs = InMemoryAppPreferences();
    service = FakeRetroAchievementsService(loginUsername: 'Player');
    container = ProviderContainer(overrides: [
      appPreferencesProvider.overrideWithValue(prefs),
      retroAchievementsServiceProvider.overrideWithValue(service),
    ]);
  });

  tearDown(() {
    container.dispose();
    resetSecureStorage();
  });

  Future<void> connect(String user, {String key = '', String? password}) =>
      container.read(retroAchievementsConnectProvider)(
        RetroAchievementsCredentials(username: user, webApiKey: key),
        password: password,
      );

  group('connect', () {
    test('rejects an empty username', () async {
      await expectLater(connect('', key: 'k'), throwsA(isA<RetroAchievementsAuthException>()));
      expect(service.calls, isEmpty);
    });

    test('rejects a username with neither password nor Web API key', () async {
      await expectLater(
        connect('Player'),
        throwsA(isA<RetroAchievementsAuthException>()
            .having((e) => e.message, 'message', contains('password, your Web API key, or both'))),
      );
      expect(prefs.values, isEmpty);
    });

    test('Web API key only: validates the key, stores it, no emulator token', () async {
      await connect('Player', key: 'webkey');

      expect(service.calls, ['profile:Player']);
      expect(prefs.getString(kRaUsernameKey), 'Player');
      expect(prefs.getString(secureKey(kRaWebApiKeySecureKey)), 'webkey');
      expect(prefs.getString(secureKey(kRaConnectTokenSecureKey)), isNull);
      expect(await container.read(retroAchievementsEmulatorLoginProvider.future), isNull);
    });

    test('password only: stores the token, never the password, and no Web API key', () async {
      await connect('Player', password: 'hunter2');

      expect(service.calls, ['login:Player']);
      expect(prefs.getString(secureKey(kRaConnectTokenSecureKey)), 'tok123');
      expect(prefs.getString(secureKey(kRaWebApiKeySecureKey)), isNull);
      expect(prefs.values.values, isNot(contains('hunter2')));

      final login = await container.read(retroAchievementsEmulatorLoginProvider.future);
      expect(login?.username, 'Player');
      expect(login?.token, 'tok123');
      expect(login?.hardcore, isFalse);
    });

    test('password and key: validates both', () async {
      await connect('Player', key: 'webkey', password: 'hunter2');
      expect(service.calls, ['profile:Player', 'login:Player']);
      expect(prefs.getString(secureKey(kRaWebApiKeySecureKey)), 'webkey');
      expect(prefs.getString(secureKey(kRaConnectTokenSecureKey)), 'tok123');
    });

    test('username casing differences are accepted for the password login', () async {
      await connect('player', password: 'pw');
      expect(prefs.getString(secureKey(kRaConnectTokenSecureKey)), 'tok123');
    });

    test('rejects a password that logs in to a different account and saves nothing', () async {
      service.loginUsername = 'SomeoneElse';
      await expectLater(connect('Player', password: 'pw'), throwsA(isA<RetroAchievementsAuthException>()));
      expect(prefs.values, isEmpty);
    });

    test('a rejected Web API key saves nothing and skips the password login', () async {
      service.profileError = const RetroAchievementsAuthException('Invalid username or Web API key.');
      await expectLater(connect('Player', key: 'bad', password: 'pw'), throwsA(isA<RetroAchievementsAuthException>()));
      expect(service.calls, ['profile:Player']);
      expect(prefs.values, isEmpty);
    });

    test('a rejected password saves nothing', () async {
      service.loginError = const RetroAchievementsAuthException('Invalid User/Password combination.');
      await expectLater(connect('Player', key: 'k', password: 'bad'), throwsA(isA<RetroAchievementsAuthException>()));
      expect(prefs.values, isEmpty);
    });

    test('re-saving the same username without a password keeps the emulator token', () async {
      await connect('Player', password: 'pw');
      await connect('PLAYER', key: 'webkey');
      expect(prefs.getString(secureKey(kRaConnectTokenSecureKey)), 'tok123');
    });

    test('switching username without a password drops the old token', () async {
      await connect('Player', password: 'pw');
      await connect('Other', key: 'webkey');
      expect(prefs.getString(secureKey(kRaConnectTokenSecureKey)), isNull);
      expect(await container.read(retroAchievementsEmulatorLoginProvider.future), isNull);
    });

    test('re-saving without a Web API key removes the stored key', () async {
      await connect('Player', key: 'webkey', password: 'pw');
      await connect('Player', password: 'pw');
      expect(prefs.getString(secureKey(kRaWebApiKeySecureKey)), isNull);
    });
  });

  group('credentials / profile providers', () {
    test('credentials resolve with only a username (no Web API key)', () async {
      await connect('Player', password: 'pw');
      final creds = await container.read(retroAchievementsCredentialsProvider.future);
      expect(creds?.username, 'Player');
      expect(creds?.hasWebApiKey, isFalse);
    });

    test('profile and game progress skip the network without a Web API key', () async {
      await connect('Player', password: 'pw');
      service.calls.clear();

      expect(await container.read(retroAchievementsProfileProvider.future), isNull);
      final sub = container.listen(retroAchievementsGameProgressProvider(1), (_, __) {});
      expect(await container.read(retroAchievementsGameProgressProvider(1).future), isNull);
      sub.close();
      expect(service.calls, isEmpty);
    });

    test('game progress is fetched when a Web API key is saved', () async {
      await connect('Player', key: 'webkey');
      final sub = container.listen(retroAchievementsGameProgressProvider(42), (_, __) {});
      final progress = await container.read(retroAchievementsGameProgressProvider(42).future);
      sub.close();
      expect(progress?.gameId, 42);
      expect(service.calls, contains('progress:42'));
    });
  });

  test('hardcore toggle is persisted and reflected in the emulator login', () async {
    await connect('Player', password: 'pw');
    await container.read(retroAchievementsSetHardcoreProvider)(true);

    expect(prefs.getBool(kRaHardcoreKey), isTrue);
    expect((await container.read(retroAchievementsEmulatorLoginProvider.future))?.hardcore, isTrue);
  });

  test('disconnect clears username, key, token and hardcore', () async {
    await connect('Player', key: 'webkey', password: 'pw');
    await container.read(retroAchievementsSetHardcoreProvider)(true);

    await container.read(retroAchievementsDisconnectProvider)();

    expect(prefs.values, isEmpty);
    expect(await container.read(retroAchievementsCredentialsProvider.future), isNull);
    expect(await container.read(retroAchievementsEmulatorLoginProvider.future), isNull);
  });
}
