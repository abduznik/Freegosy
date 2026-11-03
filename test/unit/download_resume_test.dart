import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/downloader/download_service.dart';
import 'package:freegosy/core/extraction/extraction_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:freegosy/providers/download_provider.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('resuming a paused download leaves the paused state while it downloads (#196)', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final tmp = await Directory.systemTemp.createTemp('fg');
    final dirs = DirectoryService(SharedPreferencesAppPreferences(sp));
    await dirs.setRomsRoot(tmp.path);

    const total = 400 * 1024;
    final data = List<int>.filled(total, 7);
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      var start = 0;
      final range = req.headers.value('range');
      if (range != null) start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      req.response.statusCode = start > 0 ? 206 : 200;
      req.response.headers.contentLength = total - start;
      try {
        for (var o = start; o < total; o += 16 * 1024) {
          req.response.add(data.sublist(o, o + 16 * 1024 > total ? total : o + 16 * 1024));
          await req.response.flush();
          await Future.delayed(const Duration(milliseconds: 40));
        }
        await req.response.close();
      } catch (_) {}
    });

    final svc = DownloadService(dio: Dio(), directoryService: dirs, extractionService: ExtractionService(dirs));
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      downloadServiceProvider.overrideWith((ref) async => svc),
      rommServiceProvider.overrideWithValue(null),
    ]);
    final n = c.read(downloadProvider.notifier);
    final game = Game(id: '9', name: 'Big', platformSlug: 'gba', fileName: 'big.gba', fsName: 'big.gba', fsExtension: 'gba', fileSize: total);
    final url = 'http://127.0.0.1:${server.port}/x';

    await n.startDownload(game, url);
    await Future.delayed(const Duration(milliseconds: 600));
    final before = c.read(downloadProvider)['9']!;
    n.pauseDownload('9');
    await Future.delayed(const Duration(milliseconds: 300));
    expect(c.read(downloadProvider)['9']!.isPaused, isTrue);

    await n.startDownload(game, url); // what the Resume button does
    await Future.delayed(const Duration(milliseconds: 400));
    final mid = c.read(downloadProvider)['9']!;
    expect(mid.isPaused, isFalse, reason: 'still shown as paused while bytes flow');
    expect(mid.percent, greaterThan(before.percent));
    await Future.delayed(const Duration(seconds: 3));
    final after = c.read(downloadProvider)['9']!;
    expect(after.isComplete, isTrue);
    expect(File('${tmp.path}/gba/big.gba').existsSync(), isTrue);
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  test('a download error is kept across a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final failing = Game(id: '3', name: 'Gone', platformSlug: 'gba', fileName: 'gone.gba', fsName: 'gone.gba', fsExtension: 'gba', fileSize: 1);
    final tmp = await Directory.systemTemp.createTemp('fg');
    final dirs = DirectoryService(SharedPreferencesAppPreferences(sp));
    await dirs.setRomsRoot(tmp.path);
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((r) async { r.response.statusCode = 404; await r.response.close(); });
    final svc = DownloadService(dio: Dio(), directoryService: dirs, extractionService: ExtractionService(dirs));
    List<Override> overrides() => [
          sharedPreferencesProvider.overrideWithValue(sp),
          downloadServiceProvider.overrideWith((ref) async => svc),
          rommServiceProvider.overrideWithValue(null),
        ];
    final c = ProviderContainer(overrides: overrides());
    await c.read(downloadProvider.notifier).startDownload(failing, 'http://127.0.0.1:${server.port}/x');
    await Future.delayed(const Duration(milliseconds: 500));
    expect(c.read(downloadProvider)['3']!.error, contains('404'));

    final restarted = ProviderContainer(overrides: overrides());
    restarted.read(downloadProvider.notifier);
    await Future.delayed(const Duration(milliseconds: 200));
    final back = restarted.read(downloadProvider)['3']!;
    expect(back.isPaused, isTrue);
    expect(back.status, contains('404'));
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });
}
