import 'dart:convert';
import 'dart:io';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Config (from env)
// ─────────────────────────────────────────────────────────────────────────────

const _testRomId = '6418'; // test_ps2_rom.iso on the dev instance

String get _baseUrl {
  final url = io.Platform.environment['ROMM_URL'];
  if (url == null || url.isEmpty) throw StateError('ROMM_URL not set');
  return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

String get _apiKey {
  final key = io.Platform.environment['ROMM_API_KEY'];
  if (key == null || key.isEmpty) throw StateError('ROMM_API_KEY not set');
  return key;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Fakes
// ─────────────────────────────────────────────────────────────────────────────

/// Fake DirectoryService that routes every emulator to a caller-provided
/// base dir (so each strategy's macOS path resolution lands in our temp
/// layout instead of a real install).
class _FakeDirectoryService extends DirectoryService {
  final Map<String, String> _exePaths; // emulatorId -> fake exe path
  final Map<String, String> _appSupportDirs; // emulatorName -> fake base
  final Directory _tempDir;

  _FakeDirectoryService(
    super.prefs, {
    required Map<String, String> exePaths,
    required Map<String, String> appSupportDirs,
    required Directory tempDir,
  })  : _exePaths = exePaths,
        _appSupportDirs = appSupportDirs,
        _tempDir = tempDir;

  @override
  String get linuxSyncPreset => 'default';

  @override
  Future<String?> findEmulatorExecutable(
      String emulatorId, String executableName) async {
    return _exePaths[emulatorId];
  }

  @override
  Future<String> getEmulatorAppSupportDirectory(
      String emulatorName, {String? platformSlug}) async {
    return _appSupportDirs[emulatorName] ?? _tempDir.path;
  }

  @override
  Future<String> getEmulatorSystemDirectory(
      String emulatorId, {String? platformSlug}) async {
    return _appSupportDirs[emulatorId] ?? _tempDir.path;
  }

  @override
  Future<String> getEmulatorDirectory(String emulatorId) async {
    if (emulatorId == 'temp') return _tempDir.path;
    return _appSupportDirs[emulatorId] ?? p.join(_tempDir.path, emulatorId);
  }
}

/// Fake registry that forces each platform slug to a specific emulator ID,
/// so SaveSyncService.getStrategyForSlug() resolves to the strategy under test.
class _FakeStrategyRegistry extends StrategyRegistry {
  final Map<String, String> _slugToEmulator;

  _FakeStrategyRegistry(
    DirectoryService dirService,
    SharedPreferences prefs,
    this._slugToEmulator,
  ) : super(dirService, prefs);

  @override
  String? getPreferredEmulatorId(String slug) => _slugToEmulator[slug];

  @override
  EmulatorStrategy? getStrategyForSlug(String platformSlug, {String? gameId}) {
    final emuId = _slugToEmulator[platformSlug];
    if (emuId == null) return null;
    return _FakeEmulatorStrategy(emuId);
  }
}

class _FakeEmulatorStrategy extends EmulatorStrategy {
  _FakeEmulatorStrategy(this._emulatorId);
  final String _emulatorId;
  @override
  String get name => _emulatorId;
  @override
  String get emulatorId => _emulatorId;
  @override
  List<String> get supportedSlugs => const [];
  @override
  String get windowsExecutable => 'exe';
  @override
  String get linuxExecutable => 'exe';
  @override
  bool get supportsSaveSync => true;
  @override
  DirectoryService get directoryService => throw UnimplementedError();
  @override
  String resolveSavePath(Game game) => throw UnimplementedError();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Server helpers (real HTTP against the live instance)
// ─────────────────────────────────────────────────────────────────────────────

Future<List<dynamic>> _listSaves(String romId) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('$_baseUrl/api/saves?rom_id=$romId'));
    req.headers.set('Authorization', 'Bearer $_apiKey');
    final resp = await req.close();
    final body = await resp.transform(SystemEncoding().decoder).join();
    if (resp.statusCode >= 400) return [];
    final decoded = jsonDecode(body) as List;
    return decoded;
  } finally {
    client.close(force: true);
  }
}

Future<void> _deleteSave(int id) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$_baseUrl/api/saves/delete'));
    req.headers.set('Authorization', 'Bearer $_apiKey');
    req.headers.contentType = ContentType.json;
    req.write('{"saves":[$id]}');
    final resp = await req.close();
    await resp.drain();
  } finally {
    client.close(force: true);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Harness
// ─────────────────────────────────────────────────────────────────────────────

/// Builds a minimal, structurally-valid PSP PARAM.SFO with a TITLE field.
///
/// Layout (all LE): magic `\0PSF`, version 0x00000101, key table offset,
/// data table offset, entry count, then 16-byte index entries.
Uint8List _buildParamSfo(String title) {
  final titleBytes = utf8.encode(title);
  const key = 'TITLE';
  final keyBytes = utf8.encode(key);

  const entryCount = 1;
  final headerLen = 20;
  final indexLen = 16;
  final keyTableOffset = headerLen + indexLen; // after header + index
  final dataTableOffset = keyTableOffset + keyBytes.length + 1; // + null terminator
  final dataLen = titleBytes.length + 1;

  final b = BytesBuilder();
  void addUint32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void addUint16(int v) => b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());

  // Header
  b.addByte(0x00);
  b.add(utf8.encode('PSF'));
  addUint32(0x00000101); // version
  addUint32(keyTableOffset);
  addUint32(dataTableOffset);
  addUint32(entryCount);

  // Index entry: (keyRelOffset, dataFmt=0x0204, dataLen, dataMaxLen, dataRelOffset)
  addUint16(0);
  addUint16(0x0204);
  addUint32(dataLen);
  addUint32(dataLen);
  addUint32(0);

  // Key table
  b.add(keyBytes);
  b.addByte(0);

  // Data table
  b.add(titleBytes);
  b.addByte(0);

  return b.toBytes();
}

void main() {
  test('strategy blackbox push against live RomM', () async {
    await _runAllCases();
  });
}

Future<void> _runAllCases() async {
  final temp = await Directory.systemTemp.createTemp('strategy_blackbox');
  final tempDirService = await Directory(temp.path).create();
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  // Real RommService pointed at the live server.
  final romm = RommService(
    RomMConfig(
      baseUrl: _baseUrl,
      username: '',
      password: '',
      apiKey: _apiKey,
    ),
    skipConnectivityCheck: true,
  );

  // ── Build a per-emulator fake layout ────────────────────────────────────
  final exePaths = <String, String>{};
  final appDirs = <String, String>{};

  Future<String> emuBase(String name) async {
    final dir = Directory(p.join(temp.path, name));
    await dir.create(recursive: true);
    appDirs[name] = dir.path;
    return dir.path;
  }

  Future<String> fakeExe(String emuId, String relExePath) async {
    final f = File(p.join(temp.path, relExePath));
    await f.parent.create(recursive: true);
    await f.writeAsString('fake exe');
    exePaths[emuId] = f.path;
    return f.path;
  }

  // PCSX2 (ps2): portable — memcards next to exe; folder save under saves/{Serial}.
  await fakeExe('pcsx2', 'pcsx2/pcsx2-qt.exe');
  final pcsx2Mem = File(p.join(temp.path, 'pcsx2/memcards/Mcd001.ps2'));
  await pcsx2Mem.parent.create(recursive: true);
  await pcsx2Mem.writeAsBytes(List.filled(256, 0x41));
  final pcsx2Folder = Directory(p.join(temp.path, 'pcsx2/saves/SCUS-97113'));
  await pcsx2Folder.create(recursive: true);
  await File(p.join(pcsx2Folder.path, 'savedata.bin')).writeAsBytes(List.filled(256, 0x42));

  // DuckStation (psx): portable.txt + shared + per-game memcards.
  final duckBase = await emuBase('DuckStation');
  await File(p.join(duckBase, 'portable.txt')).writeAsString('portable');
  final duckMem = Directory(p.join(duckBase, 'memcards'));
  await duckMem.create(recursive: true);
  await File(p.join(duckMem.path, 'Mcd001.mcd')).writeAsBytes(List.filled(256, 0x43));
  await File(p.join(duckMem.path, 'Suikoden II.mcd')).writeAsBytes(List.filled(256, 0x44));

  // Dolphin (wii/gc): portable User folder — needs a fake .app exe so
  // _getUserDir resolves exeDir (parent^4 of the mac .app) = temp/Dolphin
  // and finds the User/ folder next to it.
  final dolphinBase = await emuBase('Dolphin');
  await fakeExe('dolphin', 'Dolphin/Dolphin.app/Contents/MacOS/Dolphin');
  final dolphinUser = Directory(p.join(dolphinBase, 'User'));
  await dolphinUser.create(recursive: true);
  // Wii title dir: Wii/title/00010000/{hexId} where hexId = first 4 chars of game id
  final wiiHex = 'RZDE'.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  final wiiSave = Directory(p.join(dolphinUser.path, 'Wii/title/00010000/$wiiHex'));
  await wiiSave.create(recursive: true);
  await File(p.join(wiiSave.path, 'data.bin')).writeAsBytes(List.filled(256, 0x45));
  // GC save: GC/{region}/Card A — region defaults to USA unless path says EUR/PAL/JAP.
  final gcSave = Directory(p.join(dolphinUser.path, 'GC/USA/Card A'));
  await gcSave.create(recursive: true);
  await File(p.join(gcSave.path, 'RZDE01.gci')).writeAsBytes(List.filled(256, 0x46));

  // RetroArch (snes): exe-relative saves/Snes9x/{stem}.srm
  final raExe = await fakeExe('retroarch', 'retroarch/RetroArch.app/Contents/MacOS/RetroArch');
  final raExeDir = File(raExe).parent.parent.parent.parent.path;
  final raSaves = Directory(p.join(raExeDir, 'saves/Snes9x'));
  await raSaves.create(recursive: true);
  await File(p.join(raSaves.path, 'Chrono Trigger.srm')).writeAsBytes(List.filled(256, 0x47));

  // mGBA (gba): ROM-adjacent .sav — must sit next to an actual rom file.
  final gbaRomDir = Directory(p.join(temp.path, 'gba'));
  await gbaRomDir.create(recursive: true);
  await File(p.join(gbaRomDir.path, 'Metroid Fusion.gba')).writeAsBytes(List.filled(256, 0x48));
  await File(p.join(gbaRomDir.path, 'Metroid Fusion.sav')).writeAsBytes(List.filled(256, 0x49));

  // PPSSPP (psp): memstick/PSP/SAVEDATA/{folder}/ with a valid PARAM.SFO.
  final pspBase = await emuBase('ppsspp');
  final pspSaveDir = Directory(p.join(pspBase, 'PSP/SAVEDATA/ULUS10123'));
  await pspSaveDir.create(recursive: true);
  await File(p.join(pspSaveDir.path, 'PARAM.SFO')).writeAsBytes(_buildParamSfo('Loco Roco'));
  await File(p.join(pspSaveDir.path, 'DATA.BIN')).writeAsBytes(List.filled(256, 0x4a));

  // RPCS3 (ps3): portable dev_hdd0/home/00000001/savedata/{serial}
  final rpcs3Base = await emuBase('rpcs3');
  final rpcs3Save = Directory(p.join(rpcs3Base, 'dev_hdd0/home/00000001/savedata/BLUS30123'));
  await rpcs3Save.create(recursive: true);
  final rpcs3Usrdir = Directory(p.join(rpcs3Save.path, 'USRDIR'));
  await rpcs3Usrdir.create(recursive: true);
  await File(p.join(rpcs3Usrdir.path, 'save.bin')).writeAsBytes(List.filled(256, 0x4b));

  // Eden (switch): portable user/nand/user/save/0000000000000000/{profile}/{titleId}
  await fakeExe('eden', 'eden/eden');
  final edenSave = Directory(
      p.join(temp.path, 'eden/user/nand/user/save/0000000000000000/${'a' * 32}/0100000000000000'));
  await edenSave.create(recursive: true);
  await File(p.join(edenSave.path, 'main')).writeAsBytes(List.filled(256, 0x4c));

  // Cemu (wiiu): emulator dir mlc01/usr/save/00050000
  await emuBase('cemu');
  final cemuSave = Directory(p.join(temp.path, 'cemu/mlc01/usr/save/00050000'));
  await cemuSave.create(recursive: true);
  final cemuTitleDir = Directory(p.join(cemuSave.path, '0005000010116100'));
  await cemuTitleDir.create(recursive: true);
  await File(p.join(cemuTitleDir.path, 'data.bin')).writeAsBytes(List.filled(256, 0x4d));

  // Xenia (xbox360): content/{titleId}/00000001 — needs a fake exe so _getContentDir works.
  await fakeExe('xenia_canary', 'xenia/xenia_canary.exe');
  final xeniaBase = await emuBase('xenia');
  final xeniaSave = Directory(p.join(xeniaBase, 'content/545408A7/00000001'));
  await xeniaSave.create(recursive: true);
  await File(p.join(xeniaSave.path, 'save.bin')).writeAsBytes(List.filled(256, 0x4e));

  // Azahar (3ds): manual mapping → base/sdmc/{mapping}. Mapping is set per-case
  // because the switch (Eden) case overwrites the shared eden_mapping pref.
  final azaharBase = await emuBase('azahar');
  final azaharSave = Directory(p.join(azaharBase, 'sdmc/SaveData'));
  await azaharSave.create(recursive: true);
  await File(p.join(azaharSave.path, 'data.bin')).writeAsBytes(List.filled(256, 0x4f));

  final dirService = _FakeDirectoryService(
    prefs,
    exePaths: exePaths,
    appSupportDirs: appDirs,
    tempDir: tempDirService,
  );

  final slugToEmu = {
    'ps2': 'pcsx2',
    'psx': 'duckstation',
    'wii': 'dolphin',
    'gc': 'dolphin',
    'snes': 'retroarch',
    'gba': 'mgba',
    'psp': 'ppsspp',
    'ps3': 'rpcs3',
    'switch': 'eden',
    'wiiu': 'cemu',
    'xbox360': 'xenia',
    '3ds': 'azahar',
  };
  final registry = _FakeStrategyRegistry(dirService, prefs, slugToEmu);

  final service = SaveSyncService(romm, dirService, registry, prefs);

  // ── Test cases ──────────────────────────────────────────────────────────
  // Dolphin/mGBA read the actual rom file (game id / region), so those rom
  // paths must exist on disk and start with the ASCII game id for Dolphin.
  final ps2Rom = File(p.join(temp.path, 'roms/ps2/Ico (SCUS-97113).iso'));
  await ps2Rom.parent.create(recursive: true);
  await ps2Rom.writeAsBytes(List.filled(512, 0x41));

  final wiiRom = File(p.join(temp.path, 'roms/wii/Wii Test Game [RZDE01].iso'));
  await wiiRom.parent.create(recursive: true);
  final wiiRomBytes = List<int>.filled(512, 0x42);
  wiiRomBytes.setRange(0, 4, 'RZDE'.codeUnits); // game id read at offset 0
  await wiiRom.writeAsBytes(wiiRomBytes);

  final gcRom = File(p.join(temp.path, 'roms/gc/GC Test Game [RZDE01] (USA).iso'));
  await gcRom.parent.create(recursive: true);
  final gcRomBytes = List<int>.filled(512, 0x42);
  gcRomBytes.setRange(0, 4, 'RZDE'.codeUnits); // game id read at offset 0
  await gcRom.writeAsBytes(gcRomBytes);

  final gbaRom = File(p.join(temp.path, 'roms/gba/Metroid Fusion.gba'));
  await gbaRom.parent.create(recursive: true);
  await gbaRom.writeAsBytes(List.filled(512, 0x44));
  await File(p.join(gbaRom.parent.path, 'Metroid Fusion.sav')).writeAsBytes(List.filled(256, 0x45));

  final cases = <(String slug, String gameName, String romPath, String? fsName)>[
    ('ps2', 'Ico (SCUS-97113)', ps2Rom.path, null),
    ('psx', 'Suikoden II', '/roms/psx/Suikoden II.bin', null),
    ('psx', 'Random Game', '/roms/psx/Random Game.bin', null), // shared-memcard fallback
    ('wii', 'Wii Test Game', wiiRom.path, null),
    ('gc', 'GC Test Game', gcRom.path, null),
    ('snes', 'Chrono Trigger', '/roms/snes/Chrono Trigger.sfc', null),
    ('gba', 'Metroid Fusion', gbaRom.path, null),
    ('psp', 'Loco Roco', '/roms/psp/Loco Roco.iso', null),
    ('ps3', 'Test PS3 Game', '/roms/ps3/Test PS3 Game.iso', 'BLUS30123 - Test PS3 Game.iso'),
    ('switch', 'Test Switch Game', '/roms/switch/0100000000000000 - Test.nsp', null),
    ('wiiu', 'Test WiiU Game', '/roms/wiiu/Test Game.wud', null),
    // Xenia is a Windows-only emulator; its strategy hardcodes `\` separators,
    // so it cannot resolve save paths on macOS/Linux. Windows-only case.
    if (io.Platform.isWindows)
      ('xbox360', 'Test 360 Game', '/roms/xbox360/Test.iso', '545408A7.iso'),
    ('3ds', 'Test 3DS Game', '/roms/3ds/Test Game.3ds', null),
  ];

  final createdSaveIds = <int>[];
  int passed = 0, failed = 0;

  for (final (slug, name, romPath, fsName) in cases) {
    // Azahar needs the manual mapping pref; the switch (Eden) case overwrites
    // the shared eden_mapping_<id> pref with a title id, so set it per-case.
    if (slug == '3ds') {
      await prefs.setString('eden_mapping_$_testRomId', 'SaveData');
    }
    print('\n=== $slug ($name) ===');
    try {
      final before = await _listSaves(_testRomId);
      final game = Game(
        id: _testRomId,
        name: name,
        platformSlug: slug,
        fsName: fsName,
        fileSize: 0,
      );

      final ok = await service.pushSaves(game, romPath, force: true);
      if (!ok) {
        print('  FAIL: pushSaves returned false (no files found or rejected)');
        failed++;
        continue;
      }

      final after = await _listSaves(_testRomId);
      final newIds = after
          .where((s) => !before.any((b) => b['id'] == s['id']))
          .map((s) => s['id'] as int)
          .toList();
      createdSaveIds.addAll(newIds);
      print('  New server saves: ${newIds.length} → ids=$newIds');
      passed++;
    } catch (e) {
      print('  FAIL: $e');
      failed++;
    }
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────
  print('\n--- Cleanup ---');
  for (final id in createdSaveIds) {
    await _deleteSave(id);
  }
  print('Deleted ${createdSaveIds.length} test save(s)');
  await temp.delete(recursive: true);

  print('\n=== Results ===');
  print('Passed: $passed  Failed: $failed  Total: ${cases.length}');
  if (failed > 0) {
    throw StateError('$failed strategy case(s) failed');
  }
}
