import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/downloader/download_service.dart';
import 'package:freegosy/core/extraction/extraction_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/app_preferences.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> zipOf(Map<String, String> files) {
  final a = Archive();
  files.forEach((n, c) => a.addFile(ArchiveFile(n, c.length, utf8.encode(c))));
  return ZipEncoder().encode(a);
}

/// A multi-file Switch game whose RomM file name differs from its display name,
/// as most do: issues #199, #200, #201.
void main() {
  late HttpServer server;
  late Directory tmp;
  late DirectoryService dirs;
  late DownloadService svc;
  const all = {'base.nsp': 'BASE', 'update.nsp': 'UPDATE', 'alt.nsp': 'ALT'};
  const ids = {'11': 'base.nsp', '12': 'update.nsp', '13': 'alt.nsp'};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('fg');
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final fid = req.uri.queryParameters['file_ids'];
      final sel = fid == null ? all : {for (final i in fid.split(',')) ids[i]!: all[ids[i]]!};
      // RomM serves one file bare, several as a zip.
      final body = sel.length == 1 ? utf8.encode(sel.values.first) : zipOf(sel);
      req.response.headers.contentType = sel.length == 1 ? ContentType.binary : ContentType('application', 'zip');
      req.response.headers.contentLength = body.length;
      req.response.add(body);
      await req.response.close();
    });
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    dirs = DirectoryService(prefs);
    await dirs.setRomsRoot(tmp.path);
    svc = DownloadService(dio: Dio(), directoryService: dirs, extractionService: ExtractionService(dirs));
  });
  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  Game game() => Game(
        id: '5', name: 'Zelda Bundle', platformSlug: 'switch', fileName: 'zelda_bundle_v1', fsName: 'zelda_bundle_v1',
        fsExtension: '', fileSize: 100, hasMultipleFiles: true,
        files: [for (final e in ids.entries) {'id': int.parse(e.key), 'file_name': e.value, 'file_size_bytes': 10}],
      );

  String url(String fileIds) => 'http://127.0.0.1:${server.port}/api/roms/5/content/zelda_bundle_v1?file_ids=$fileIds';

  List<String> tree() => (tmp.listSync(recursive: true)..sort((a, b) => a.path.compareTo(b.path)))
      .map((e) => e.path.substring(tmp.path.length + 1)).toList();

  test('Download All leaves one folder with every file, and delete removes it', () async {
    final g = game();
    await svc.download(g, url('11,12,13')).last;
    expect(tree(), ['switch', 'switch/Zelda Bundle', 'switch/Zelda Bundle/alt.nsp', 'switch/Zelda Bundle/base.nsp', 'switch/Zelda Bundle/update.nsp']);
    expect(await dirs.isRomDownloaded(g), isTrue);

    await dirs.deleteRom(g);
    expect(tree(), ['switch']);
    expect(await dirs.isRomDownloaded(g), isFalse);
  });

  test('selected files land in the game folder, and more can be added later', () async {
    final g = game();
    var last = await svc.download(g, url('11,12'), force: true).last;
    expect(last.error, isNull);
    expect(tree().where((e) => e.endsWith('.nsp')), ['switch/Zelda Bundle/base.nsp', 'switch/Zelda Bundle/update.nsp']);
    expect(await dirs.isRomDownloaded(g), isTrue, reason: 'a partial download is playable');

    // One file alone comes back bare, not zipped.
    last = await svc.download(g, url('13'), force: true, singleFileName: 'alt.nsp').last;
    expect(last.isComplete, isTrue);
    expect(tree().where((e) => e.endsWith('.nsp')).length, 3);
    expect(tree().where((e) => e.endsWith('.nsp')).every((e) => e.startsWith('switch/Zelda Bundle/')), isTrue);
    expect(tree().any((e) => e.endsWith('.download') || e.endsWith('.part') || e.endsWith('.zip')), isFalse);

    await dirs.deleteRom(g);
    expect(tree(), ['switch']);
  });

  test('without force, an already downloaded game is not fetched again', () async {
    final g = game();
    await svc.download(g, url('11,12,13')).last;
    final again = await svc.download(g, url('11,12,13')).last;
    expect(again.isComplete, isTrue);
  });

  test('an empty folder left by an older download is not the game, and delete clears it', () async {
    final g = game();
    Directory('${tmp.path}/switch/zelda_bundle_v1').createSync(recursive: true);
    expect(await dirs.isRomDownloaded(g), isFalse);

    await svc.download(g, url('11,12,13')).last;
    Directory('${tmp.path}/switch/zelda_bundle_v1').createSync();
    expect(await dirs.isRomDownloaded(g), isTrue);
    await dirs.deleteRom(g);
    expect(tree(), ['switch']);
  });
}
