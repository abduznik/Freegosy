import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/retroachievements/retroachievements_models.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/providers/retroachievements_provider.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers/fake_retroachievements.dart';

void main() {
  group('RommService (HTTP)', () {
    const baseUrl = 'https://romm.test';
    late Dio dio;
    late DioAdapter adapter;
    late RommService romm;
    final sent = <RequestOptions>[];

    setUp(() {
      sent.clear();
      dio = Dio(BaseOptions(baseUrl: baseUrl));
      adapter = DioAdapter(dio: dio);
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        sent.add(o);
        h.next(o);
      }));
      romm = RommService(RomMConfig(baseUrl: baseUrl, username: '', password: '', apiKey: 'k'), dio: dio);
    });

    group('fetchCapabilities reads RA_API_ENABLED', () {
      for (final (value, expected) in [(true, true), (false, false), (null, null)]) {
        test('$value → $expected', () async {
          adapter.onGet('/api/heartbeat', (s) => s.reply(200, {
                'SYSTEM': {'VERSION': '4.9.0'},
                'METADATA_SOURCES': {'RA_API_ENABLED': ?value},
              }));
          expect((await romm.fetchCapabilities()).retroAchievementsEnabled, expected);
        });
      }

      test('unknown when the heartbeat fails', () async {
        adapter.onGet('/api/heartbeat', (s) => s.reply(500, {}));
        expect((await romm.fetchCapabilities()).retroAchievementsEnabled, isNull);
      });
    });

    test('getRetroAchievementsLink returns the RomM user id and RA username', () async {
      adapter.onGet('/api/users/me', (s) => s.reply(200, {'id': 3, 'username': 'me', 'ra_username': 'Player'}));
      final link = await romm.getRetroAchievementsLink();
      expect(link?.id, 3);
      expect(link?.raUsername, 'Player');
    });

    test('getRetroAchievementsLink treats an empty ra_username as unlinked', () async {
      adapter.onGet('/api/users/me', (s) => s.reply(200, {'id': 3, 'ra_username': ''}));
      expect((await romm.getRetroAchievementsLink())?.raUsername, isNull);
    });

    test('getRetroAchievementsLink is null on failure', () async {
      adapter.onGet('/api/users/me', (s) => s.reply(401, {}));
      expect(await romm.getRetroAchievementsLink(), isNull);
    });

    test('setRetroAchievementsUsername PUTs a form with only ra_username', () async {
      adapter.onPut('/api/users/3', (s) => s.reply(200, {'id': 3}), data: Matchers.any);
      await romm.setRetroAchievementsUsername(3, 'Player');

      final form = sent.single.data as FormData;
      expect(sent.single.method, 'PUT');
      expect(Map.fromEntries(form.fields), {'ra_username': 'Player'});
    });

    test('setRetroAchievementsUsername throws when RomM refuses', () async {
      adapter.onPut('/api/users/3', (s) => s.reply(403, {'detail': 'Forbidden'}), data: Matchers.any);
      expect(() => romm.setRetroAchievementsUsername(3, 'Player'), throwsA(isA<DioException>()));
    });

    test('refreshRetroAchievements posts a full (non-incremental) sync', () async {
      adapter.onPost('/api/users/3/ra/refresh', (s) => s.reply(200, null), data: {'incremental': false});
      expect(await romm.refreshRetroAchievements(3), isTrue);
      expect(sent.single.receiveTimeout, const Duration(minutes: 3));
    });

    test('refreshRetroAchievements returns false instead of throwing', () async {
      adapter.onPost('/api/users/3/ra/refresh', (s) => s.reply(403, {}), data: {'incremental': false});
      expect(await romm.refreshRetroAchievements(3), isFalse);
    });
  });

  group('RommRetroAchievementsStatus', () {
    test('isLinkedTo ignores case', () {
      const s = RommRetroAchievementsStatus(serverEnabled: true, rommUserId: 1, linkedUsername: 'Player');
      expect(s.isLinkedTo('player'), isTrue);
      expect(s.canLink('player'), isFalse);
      expect(s.canLink('Other'), isTrue);
    });

    test('cannot link when the server has RA disabled or the user is unknown', () {
      expect(const RommRetroAchievementsStatus(serverEnabled: false, rommUserId: 1).canLink('p'), isFalse);
      expect(const RommRetroAchievementsStatus(serverEnabled: true).canLink('p'), isFalse);
      expect(const RommRetroAchievementsStatus().canLink('p'), isFalse);
    });
  });

  group('providers', () {
    late FakeRommRaService romm;
    late ProviderContainer container;

    ProviderContainer make(RommService? service) => ProviderContainer(overrides: [
          rommServiceProvider.overrideWithValue(service),
        ]);

    setUp(() {
      romm = FakeRommRaService(linkedUsername: null);
      container = make(romm);
    });
    tearDown(() => container.dispose());

    test('status is unknown without a RomM connection', () async {
      final c = make(null);
      addTearDown(c.dispose);
      final status = await c.read(rommRetroAchievementsStatusProvider.future);
      expect(status.serverEnabled, isNull);
    });

    test('a server without RA reports disabled and skips the profile lookup', () async {
      romm.raEnabled = false;
      final status = await container.read(rommRetroAchievementsStatusProvider.future);
      expect(status.serverEnabled, isFalse);
      expect(romm.calls, isEmpty);
    });

    test('a server with RA reports the linked username', () async {
      romm.linkedUsername = 'Player';
      final status = await container.read(rommRetroAchievementsStatusProvider.future);
      expect(status.serverEnabled, isTrue);
      expect(status.rommUserId, 5);
      expect(status.isLinkedTo('Player'), isTrue);
    });

    test('linking sets the username, syncs, and refreshes the status', () async {
      expect((await container.read(rommRetroAchievementsStatusProvider.future)).linkedUsername, isNull);

      final synced = await container.read(linkRommRetroAchievementsProvider)('Player');

      expect(synced, isTrue);
      expect(romm.calls, containsAllInOrder(['set:5:Player', 'refresh:5']));
      expect((await container.read(rommRetroAchievementsStatusProvider.future)).isLinkedTo('Player'), isTrue);
    });

    test('linking reports a failed sync without throwing', () async {
      romm.refreshSucceeds = false;
      expect(await container.read(linkRommRetroAchievementsProvider)('Player'), isFalse);
    });

    test('linking fails when the RomM user is unknown', () async {
      romm.userId = null;
      await expectLater(container.read(linkRommRetroAchievementsProvider)('Player'), throwsStateError);
      expect(romm.calls.where((c) => c.startsWith('set:')), isEmpty);
    });
  });
}
