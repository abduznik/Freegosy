import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/romm/romm_state.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// Fails every request with a connection error that carries the request's own
/// options, like Dio's real adapters do (the retry logic reads them back).
class _ConnectionLostAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    throw DioException.connectionError(
        requestOptions: options, reason: 'connection lost');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const baseUrl = 'https://romm.example.com';
  late RommService service;
  late Dio dio;
  late DioAdapter adapter;
  late Directory tmp;
  late File stateFile;

  /// Options of every request that reached the adapter, retries included.
  late List<RequestOptions> requests;

  setUp(() async {
    dio = Dio(BaseOptions(baseUrl: baseUrl));
    adapter = DioAdapter(dio: dio);
    requests = [];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.next(options);
    }));
    service = RommService(
      RomMConfig(baseUrl: baseUrl, username: '', password: '', apiKey: 'key'),
      dio: dio,
      skipConnectivityCheck: true,
    );
    tmp = await Directory.systemTemp.createTemp('romm_states_client');
    stateFile = File('${tmp.path}/SCUS-97113 (A1B2C3D4).01.p2s')
      ..writeAsBytesSync(List.filled(256, 7));
  });

  tearDown(() async {
    // On Windows the mock adapter never drains the multipart file stream, so
    // the OS may still hold the file open. Cleanup is best-effort.
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // Leaked temp dir under the OS temp folder; harmless.
    }
  });

  Map<String, dynamic> stateJson(int id, String name) => {
        'id': id,
        'rom_id': 42,
        'file_name': name,
        'updated_at': '2026-01-01T00:00:00Z',
      };

  test('listStates parses a bare list', () async {
    adapter.onGet(
      '/api/states',
      (server) => server.reply(200, [stateJson(7, 'a.p2s')]),
      queryParameters: {'rom_id': '42'},
    );

    final states = await service.listStates('42');

    expect(states, hasLength(1));
    expect(states.first.id, 7);
    expect(states.first.fileName, 'a.p2s');
    expect(states.first.updatedAt, '2026-01-01T00:00:00Z');
  });

  test('listStates parses an {items: [...]} envelope', () async {
    adapter.onGet(
      '/api/states',
      (server) => server.reply(200, {'items': [stateJson(8, 'b.p2s')]}),
      queryParameters: {'rom_id': '42'},
    );

    final states = await service.listStates('42');

    expect(states.single.id, 8);
  });

  test('uploadState POSTs the stateFile with the emulator id', () async {
    adapter.onPost(
      '/api/states',
      (server) => server.reply(200, stateJson(9, 'SCUS-97113 (A1B2C3D4).01.p2s')),
      data: Matchers.any,
      queryParameters: {'rom_id': '42', 'emulator': 'pcsx2'},
    );

    final state = await service.uploadState('42', stateFile,
        fileName: 'SCUS-97113 (A1B2C3D4).01.p2s', emulator: 'pcsx2');

    expect(state.id, 9);
  });

  test('uploadState without an emulator sends no emulator parameter', () async {
    adapter.onPost('/api/states', (server) => server.reply(200, {'id': 5, 'file_name': 'a.p2s'}),
        queryParameters: {'rom_id': '42'}, data: Matchers.any);
    await service.uploadState('42', stateFile, fileName: 'a.p2s');
    expect(requests.single.queryParameters.containsKey('emulator'), isFalse);
  });

  test('uploadState sends screenshotFile when given', () async {
    adapter.onPost('/api/states', (server) => server.reply(200, {'id': 5, 'file_name': 'a.p2s'}),
        queryParameters: {'rom_id': '42', 'emulator': 'pcsx2'}, data: Matchers.any);
    await service.uploadState('42', stateFile, fileName: 'a.p2s', emulator: 'pcsx2',
        screenshot: Uint8List.fromList([1, 2, 3]));
    final form = requests.single.data as FormData;
    expect(form.files.map((f) => f.key), containsAll(['stateFile', 'screenshotFile']));
    expect(form.files.firstWhere((f) => f.key == 'screenshotFile').value.filename, 'a.p2s.png');
  });

  test('updateState sends screenshotFile when given, and only stateFile otherwise', () async {
    adapter.onPut('/api/states/7', (server) => server.reply(200, {'id': 7, 'file_name': 'a.p2s'}),
        data: Matchers.any);
    await service.updateState(7, stateFile, fileName: 'a.p2s', screenshot: Uint8List.fromList([9]));
    await service.updateState(7, stateFile, fileName: 'a.p2s');
    expect((requests[0].data as FormData).files.map((f) => f.key), ['stateFile', 'screenshotFile']);
    expect((requests[1].data as FormData).files.map((f) => f.key), ['stateFile']);
  });

  test('listStates reads emulator and screenshot download path, leniently', () async {
    adapter.onGet('/api/states', (server) => server.reply(200, [
          {'id': 1, 'file_name': 'a.p2s', 'updated_at': 'u1', 'emulator': 'pcsx2',
           'screenshot': {'id': 3, 'download_path': '/api/raw/assets/s/3.png'}},
          {'id': 2, 'file_name': 'b.p2s', 'updated_at': 'u2'},
          {'id': 4, 'file_name': 'c.p2s', 'emulator': null, 'screenshot': null},
        ]), queryParameters: {'rom_id': '42'});
    final states = await service.listStates('42');
    expect(states[0].emulator, 'pcsx2');
    expect(states[0].screenshotUrl, '/api/raw/assets/s/3.png');
    expect(states[1].emulator, isNull);
    expect(states[1].screenshotUrl, isNull);
    expect(states[2].screenshotUrl, isNull);
  });

  test('downloadStateScreenshot rejects an absolute URL and makes no request', () async {
    await expectLater(
      service.downloadStateScreenshot('https://evil.example/x.png'),
      throwsA(isA<ArgumentError>()),
    );
    expect(requests, isEmpty);
  });

  test('downloadStateScreenshot: authenticated, bounded, no retry', () async {
    adapter.onGet(
        '/api/raw/assets/s/3.png', (server) => server.reply(200, Uint8List.fromList([1, 2, 3])));
    final bytes = await service.downloadStateScreenshot('/api/raw/assets/s/3.png');
    expect(bytes, Uint8List.fromList([1, 2, 3]));
    final options = requests.single;
    expect(options.receiveTimeout, RommService.stateDownloadInactivityTimeout);
    expect(options.extra['no_retry'], isTrue);
    expect(options.headers['Authorization'], isNotNull);
  });

  test('updateState PUTs to the state id', () async {
    adapter.onPut(
      '/api/states/7',
      (server) => server.reply(200, stateJson(7, 'a.p2s')),
      data: Matchers.any,
    );

    final state = await service.updateState(7, stateFile, fileName: 'a.p2s');

    expect(state.id, 7);
  });

  test('updateState maps a 404 to RommStateNotFoundException', () async {
    adapter.onPut(
      '/api/states/7',
      (server) => server.reply(404, {'detail': 'State not found'}),
      data: Matchers.any,
    );

    expect(
      () => service.updateState(7, stateFile, fileName: 'a.p2s'),
      throwsA(isA<RommStateNotFoundException>()),
    );
  });

  test('downloadState returns the raw bytes', () async {
    adapter.onGet(
      '/api/states/7/content',
      (server) => server.reply(200, Uint8List.fromList([1, 2, 3])),
    );

    final bytes = await service.downloadState(7);

    expect(bytes, Uint8List.fromList([1, 2, 3]));
  });

  test('downloadState maps a 404 to RommStateNotFoundException', () async {
    adapter.onGet(
      '/api/states/7/content',
      (server) => server.reply(404, {'detail': 'State not found'}),
    );

    expect(() => service.downloadState(7), throwsA(isA<RommStateNotFoundException>()));
  });

  group('transfer bounds', () {
    test('downloadState carries the 30 s inactivity timeout and the no-retry flag', () async {
      adapter.onGet(
        '/api/states/7/content',
        (server) => server.reply(200, Uint8List.fromList([1, 2, 3])),
      );

      await service.downloadState(7);

      expect(RommService.stateDownloadInactivityTimeout, const Duration(seconds: 30));
      final options = requests.single;
      expect(options.receiveTimeout, const Duration(seconds: 30));
      expect(options.extra['no_retry'], isTrue);
      expect(options.headers['Authorization'], 'Bearer key', reason: 'still authenticated');
      expect(options.responseType, ResponseType.bytes);
    });

    test('a failed download makes exactly one request', () async {
      dio.httpClientAdapter = _ConnectionLostAdapter();

      await expectLater(service.downloadState(7), throwsA(isA<DioException>()));

      expect(requests, hasLength(1), reason: 'the sync stops at the first failed download');
    });

    test('other requests are still retried after a connection error', () async {
      dio.httpClientAdapter = _ConnectionLostAdapter();

      await expectLater(service.listStates('42'), throwsA(isA<DioException>()));

      expect(requests, hasLength(3), reason: 'first attempt plus the two retries');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('uploads and updates keep the 5 minute timeouts', () async {
      adapter.onPost(
        '/api/states',
        (server) => server.reply(200, stateJson(9, 'a.p2s')),
        data: Matchers.any,
        queryParameters: {'rom_id': '42', 'emulator': 'pcsx2'},
      );
      adapter.onPut(
        '/api/states/7',
        (server) => server.reply(200, stateJson(7, 'a.p2s')),
        data: Matchers.any,
      );

      await service.uploadState('42', stateFile, fileName: 'a.p2s', emulator: 'pcsx2');
      await service.updateState(7, stateFile, fileName: 'a.p2s');

      expect(requests, hasLength(2));
      for (final options in requests) {
        expect(options.receiveTimeout, const Duration(minutes: 5));
        expect(options.sendTimeout, const Duration(minutes: 5));
        expect(options.extra['no_retry'], isNull);
      }
    });
  });
}
