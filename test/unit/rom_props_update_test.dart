import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stand-in for RomM's `PUT /api/roms/{id}/props` with either contract:
/// 4.8 reads `{"data": {...}}`, 4.9+ reads the flat body (query params for the
/// last-played flags). Like the real server, unknown body fields are ignored,
/// so a wrongly shaped request still gets 200 and saves nothing.
class _FakeRomm implements HttpClientAdapter {
  final String version;
  final Map<String, dynamic> user = {'status': null, 'rating': 0, 'completion': 0, 'backlogged': false, 'now_playing': false};
  final requests = <String>[];
  final bool heartbeatDown;
  _FakeRomm(this.version, {this.heartbeatDown = false});

  bool get _new49 => !version.startsWith('4.8') && !version.startsWith('4.7');

  ResponseBody _json(Object body, [int code = 200]) =>
      ResponseBody.fromString(jsonEncode(body), code, headers: {Headers.contentTypeHeader: ['application/json']});

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    if (o.path == '/api/heartbeat' && heartbeatDown) return _json({}, 503);
    if (o.path == '/api/heartbeat') return _json({'SYSTEM': {'VERSION': version}});
    if (o.method == 'PUT' && o.path.endsWith('/props')) {
      final body = Map<String, dynamic>.from(o.data as Map);
      requests.add(_new49 ? 'flat' : 'nested');
      final fields = _new49 ? body : Map<String, dynamic>.from(body['data'] as Map? ?? {});
      if (!_new49 && body['data'] == null) return _json({'detail': 'field required'}, 422);
      for (final k in user.keys) {
        if (fields.containsKey(k)) user[k] = fields[k];
      }
      return _json(Map<String, dynamic>.from(user));
    }
    return _json({}, 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  for (final version in ['4.8.1', '4.9.0', '5.1.0']) {
    test('status and rating are saved on RomM $version', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final fake = _FakeRomm(version);
      final dio = Dio(BaseOptions(baseUrl: 'https://romm.test'))..httpClientAdapter = fake;
      final service = RommService(
        RomMConfig(baseUrl: 'https://romm.test', username: '', password: '', apiKey: 'k'),
        dio: dio,
      );

      final ok = await service.updateRomProps('7', prefs, status: 'Finished', rating: 8);

      // ignore: avoid_print
      print('RomM $version -> saved=$ok, server now has status=${fake.user['status']} rating=${fake.user['rating']}');
      expect(ok, isTrue);
      expect(fake.user['status'], 'finished');
      expect(fake.user['rating'], 8);
    });
  }

  test('a 4.9+ server whose version could not be read still gets the right shape (retry)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final fake = _FakeRomm('5.1.0', heartbeatDown: true);
    final dio = Dio(BaseOptions(baseUrl: 'https://romm.test'))..httpClientAdapter = fake;
    final service = RommService(
      RomMConfig(baseUrl: 'https://romm.test', username: '', password: '', apiKey: 'k'),
      dio: dio,
    );

    expect(await service.updateRomProps('7', prefs, status: 'retired'), isTrue);
    expect(fake.user['status'], 'retired');
    expect(fake.requests, ['flat', 'flat'], reason: 'first the 4.8 shape (ignored), then the flat one');
  });

  test('a failing server is reported as failed', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final dio = Dio(BaseOptions(baseUrl: 'https://romm.test'))
      ..httpClientAdapter = _FakeRomm('5.1.0')
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) => o.path.endsWith('/props') ? h.resolve(Response(requestOptions: o, statusCode: 403)) : h.next(o)));
    final service = RommService(
      RomMConfig(baseUrl: 'https://romm.test', username: '', password: '', apiKey: 'k'),
      dio: dio,
    );
    expect(await service.updateRomProps('7', prefs, status: 'finished'), isFalse);
  });
}
