/// Save sync integration test suite.
/// Tests push/pull round-trip for all macOS-supported platforms
/// against a live RomM server.
///
/// Usage: ROMM_URL=... ROMM_API_KEY=... dart run tool/integration_tests/save_sync_integration.dart
///
/// This test:
/// 1. Finds a game for each platform on the server
/// 2. Creates a fake save file with platform-specific content
/// 3. Pushes it to the server
/// 4. Pulls it back
/// 5. Verifies content matches
/// 6. Cleans up all test saves

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

// ── Config ─────────────────────────────────────────────────────────────

String get _baseUrl {
  final url = Platform.environment['ROMM_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('Error: ROMM_URL not set');
    exit(1);
  }
  return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

String get _apiKey {
  final key = Platform.environment['ROMM_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('Error: ROMM_API_KEY not set');
    exit(1);
  }
  return key;
}

Map<String, String> get _headers => {
  'Authorization': 'Bearer $_apiKey',
  'X-Api-Key': _apiKey,
  'Accept': 'application/json',
  'User-Agent': 'Freegosy-Test/0.5.10',
};

// ── API helpers ────────────────────────────────────────────────────────

Future<List<dynamic>> _getList(String path) async {
  final resp = await http.get(Uri.parse('$_baseUrl$path'), headers: _headers)
      .timeout(const Duration(seconds: 60));
  if (resp.statusCode >= 400) {
    stderr.writeln('HTTP ${resp.statusCode} on GET $path');
    return [];
  }
  final decoded = jsonDecode(resp.body);
  if (decoded is List) return decoded;
  return (decoded['items'] ?? decoded['roms'] ?? decoded['platforms'] ?? []) as List;
}

Future<Map<String, dynamic>?> _getGame(String id) async {
  final resp = await http.get(Uri.parse('$_baseUrl/api/roms/$id'), headers: _headers)
      .timeout(const Duration(seconds: 15));
  if (resp.statusCode >= 400) return null;
  return jsonDecode(resp.body) as Map<String, dynamic>;
}

Future<int> _pushSave(String romId, String filename, Uint8List data) async {
  final uri = Uri.parse('$_baseUrl/api/saves').replace(queryParameters: {
    'rom_id': romId,
    'emulator': 'freegosy',
    'slot': 'freegosy',
    'overwrite': 'true',
  });

  final tmpDir = await Directory.systemTemp.createTemp('save_test_');
  final tmpFile = File('${tmpDir.path}/$filename');
  await tmpFile.writeAsBytes(data);

  final req = http.MultipartRequest('POST', uri);
  req.headers.addAll(_headers);
  req.files.add(await http.MultipartFile.fromPath('saveFile', tmpFile.path));

  final resp = await req.send().timeout(const Duration(minutes: 2));
  final body = await resp.stream.bytesToString();
  await tmpDir.delete(recursive: true);

  if (resp.statusCode >= 300) {
    stderr.writeln('  Push failed: ${resp.statusCode} $body');
    return -1;
  }
  final result = jsonDecode(body);
  return result['id'] ?? -1;
}

Future<Uint8List?> _pullSave(String downloadUrl) async {
  final fullUrl = downloadUrl.startsWith('http') ? downloadUrl : '$_baseUrl$downloadUrl';
  final resp = await http.get(
    Uri.parse(fullUrl),
    headers: {..._headers, 'Accept': 'application/octet-stream'},
  ).timeout(const Duration(seconds: 30));

  if (resp.statusCode != 200) return null;
  return resp.bodyBytes;
}

Future<List<dynamic>> _listSaves(String romId) async {
  return _getList('/api/saves?rom_id=$romId');
}

Future<void> _deleteSaves(List<String> ids) async {
  if (ids.isEmpty) return;
  await http.post(
    Uri.parse('$_baseUrl/api/saves/delete'),
    headers: {..._headers, 'Content-Type': 'application/json'},
    body: jsonEncode({'saves': ids}),
  ).timeout(const Duration(seconds: 15));
}

// ── Test platforms ─────────────────────────────────────────────────────

/// Each entry: (platform_slug, expected_save_extension, emulator_label)
const testPlatforms = [
  // RetroArch cores
  ('gba', '.srm', 'RetroArch/mGBA'),
  ('snes', '.srm', 'RetroArch/Snes9x'),
  ('n64', '.srm', 'RetroArch/Mupen64Plus'),
  ('nes', '.srm', 'RetroArch/FCEUmm'),
  ('nds', '.srm', 'RetroArch/melonDS'),
  ('psx', '.srm', 'RetroArch/PCSX-ReARMed'),
  ('psp', '.srm', 'RetroArch/PPSSPP'),
  ('dc', '.srm', 'RetroArch/Flycast'),
  ('atari2600', '.srm', 'RetroArch/Stella'),
  // Standalone emulators
  ('ps2', '.ps2', 'PCSX2'),
  ('switch', '.dat', 'Ryujinx'),
  ('ps3', '.bin', 'RPCS3'),
  ('wii', '.gci', 'Dolphin'),
  ('gc', '.gci', 'Dolphin'),
];

// ── Test runner ────────────────────────────────────────────────────────

Future<void> main() async {
  // Optional filter: --platform=<slug> (or PLATFORM env var) to run one.
  var filter = (Platform.environment['PLATFORM'] ?? '').toLowerCase();
  for (final arg in Platform.executableArguments) {
    if (arg.startsWith('--platform=')) {
      filter = arg.substring('--platform='.length).toLowerCase();
      break;
    }
  }

  print('=== Save Sync Integration Test Suite ===');
  print('Server: $_baseUrl\n');

  // Verify connectivity
  try {
    final hbResp = await http.get(Uri.parse('$_baseUrl/api/heartbeat'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    final hb = jsonDecode(hbResp.body);
    print('Server version: ${hb["SYSTEM"]["VERSION"]}\n');
  } catch (e) {
    stderr.writeln('Cannot connect to server: $e');
    exit(1);
  }

  // Get platforms
  final platforms = await _getList('/api/platforms');
  final platformMap = <String, dynamic>{};
  for (final p in platforms) {
    platformMap[p['slug']] = p;
  }

  int passed = 0;
  int failed = 0;
  int skipped = 0;
  final createdSaveIds = <String>[];

  for (final (slug, ext, emulator) in testPlatforms) {
    if (filter.isNotEmpty && slug != filter) {
      print('--- $slug ($emulator) ---');
      print('  SKIP: filtered out');
      skipped++;
      continue;
    }
    print('--- $slug ($emulator) ---');

    // Find platform
    final plat = platformMap[slug];
    if (plat == null) {
      print('  SKIP: Platform "$slug" not found on server');
      skipped++;
      continue;
    }

    // Find a game for this platform
    final platId = plat['id'];
    final games = await _getList('/api/roms?limit=10&platform_ids=$platId&order_by=name');
    if (games.isEmpty) {
      print('  SKIP: No games for platform "$slug"');
      skipped++;
      continue;
    }

    final game = games.first;
    final gameId = game['id'].toString();
    final gameName = game['name'] ?? '?';
    print('  Game: $gameName (id=$gameId)');

    // Create fake save with platform-specific marker
    final marker = 'FREEGOSY_TEST_${slug.toUpperCase()}_${DateTime.now().millisecondsSinceEpoch}';
    final fakeData = Uint8List(256);
    final markerBytes = utf8.encode(marker);
    fakeData.setRange(0, markerBytes.length.clamp(0, fakeData.length), markerBytes);
    // Add platform slug at offset 200 for verification
    final slugBytes = utf8.encode(slug);
    fakeData.setRange(200, (200 + slugBytes.length).clamp(0, fakeData.length), slugBytes);

    final saveFilename = 'test_save$ext';

    // Step 1: Cleanup existing test saves
    final existingSaves = await _listSaves(gameId);
    final testSaveIds = existingSaves
        .where((s) => s['emulator'] == 'freegosy' && s['slot'] == 'freegosy')
        .map((s) => s['id'].toString())
        .toList();
    if (testSaveIds.isNotEmpty) {
      await _deleteSaves(testSaveIds);
      print('  Cleaned ${testSaveIds.length} old test save(s)');
    }

    // Step 2: Push
    final saveId = await _pushSave(gameId, saveFilename, fakeData);
    if (saveId == -1) {
      print('  FAIL: Push failed');
      failed++;
      continue;
    }
    createdSaveIds.add(saveId.toString());
    print('  Pushed: save_id=$saveId (${fakeData.length} bytes)');

    // Step 3: Verify on server
    final saves = await _listSaves(gameId);
    final ourSave = saves.firstWhere(
      (s) => s['id'].toString() == saveId.toString(),
      orElse: () => null,
    );
    if (ourSave == null) {
      print('  FAIL: Save not found on server after push');
      failed++;
      continue;
    }
    final serverSize = ourSave['file_size_bytes'] ?? 0;
    if (serverSize != fakeData.length) {
      print('  FAIL: Size mismatch (sent ${fakeData.length}, server has $serverSize)');
      failed++;
      continue;
    }
    print('  Verified on server: size=$serverSize ✓');

    // Step 4: Pull back
    final downloadUrl = ourSave['download_path'] ?? ourSave['url'];
    if (downloadUrl == null) {
      print('  FAIL: No download URL in save response');
      failed++;
      continue;
    }
    final pulledData = await _pullSave(downloadUrl);
    if (pulledData == null) {
      print('  FAIL: Pull failed');
      failed++;
      continue;
    }
    print('  Pulled: ${pulledData.length} bytes');

    // Step 5: Verify round-trip
    if (pulledData.length != fakeData.length) {
      print('  FAIL: Round-trip size mismatch (sent ${fakeData.length}, got ${pulledData.length})');
      failed++;
      continue;
    }

    bool contentMatch = true;
    for (int i = 0; i < fakeData.length; i++) {
      if (pulledData[i] != fakeData[i]) {
        contentMatch = false;
        print('  FAIL: Byte mismatch at offset $i (sent ${fakeData[i]}, got ${pulledData[i]})');
        break;
      }
    }

    if (contentMatch) {
      print('  Round-trip: ✓ PASS');
      passed++;
    } else {
      failed++;
    }
  }

  // Cleanup all test saves
  print('\n--- Cleanup ---');
  if (createdSaveIds.isNotEmpty) {
    await _deleteSaves(createdSaveIds);
    print('Deleted ${createdSaveIds.length} test save(s)');
  }

  // Summary
  print('\n=== Results ===');
  print('Passed:  $passed');
  print('Failed:  $failed');
  print('Skipped: $skipped');
  print('Total:   ${passed + failed + skipped}');

  if (failed > 0) {
    exit(1);
  }
}
