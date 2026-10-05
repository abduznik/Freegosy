import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/save/backup_entry.dart';
import 'package:freegosy/core/save/backup_repository.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/save/catalog/save_catalog_sources.dart';
import 'package:freegosy/core/save/catalog/save_entry.dart';
import 'package:freegosy/core/save/catalog/save_maker.dart';

class _Sources implements SaveCatalogSources {
  _Sources({this.local = const [], this.backupRows = const [], this.romm});
  final List<SaveEntry> local;
  final List<SaveEntry> backupRows;
  final List<Map<String, dynamic>>? romm;
  @override
  Set<String> get emulatorIds => const {'retroarch', 'ares'};
  @override
  Future<List<SaveEntry>> localSaves(Game game, String romPath) async => local;
  @override
  List<SaveEntry> backups(Game game) => backupRows;
  @override
  Future<List<Map<String, dynamic>>?> rommSaves(Game game) async => romm;
}

class _Repo extends BackupRepository {
  _Repo(this.entries);
  final List<BackupEntry> entries;
  @override
  List<BackupEntry> getEntries(String romId) => entries;
}

void main() {
  final game = Game(id: '1', name: 'Mario Kart 64', platformSlug: 'n64', fileSize: 0);
  Map<String, dynamic> romm(String name, String tag, String time, {String slot = 'freegosy'}) =>
      {'file_name': name, 'emulator': tag, 'slot': slot, 'updated_at': time};
  SaveEntry local(String emulator, DateTime t) =>
      SaveEntry(source: SaveSource.local, fileName: emulator, savedAt: t, maker: SaveMaker(emulator), tag: emulator);

  test('a RetroArch backup is listed with the core it was made with', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final dirs = DirectoryService(prefs);
    final registry = StrategyRegistry(dirs, prefs);
    final sources = LiveSaveCatalogSources(
      sync: SaveSyncService(RommService(RomMConfig(baseUrl: '', username: '', password: '')), dirs, registry, prefs),
      registry: registry,
      backupRepository: _Repo([
        BackupEntry(timestamp: DateTime(2026), md5Hash: 'm', localZipPath: '/b/ra.zip', emulatorId: 'retroarch', coreId: 'mgba'),
      ]),
      rommService: null,
      installed: const {},
    );
    final row = sources.backups(game).single;
    expect(row.maker, const SaveMaker('retroarch', coreId: 'mgba'));
    expect(row.tag, 'mgba');
  });

  test('RomM saves group by slot and tag, newest first, older versions folded', () async {
    final c = await loadSaveCatalog(game, '/roms/mk.z64', _Sources(romm: [
      romm('a.zip', 'freegosy', '2026-10-01T07:56:29Z'),
      romm('b.srm', 'mupen64plus_next', '2026-09-28T16:40:00Z'),
      romm('c.zip', 'freegosy', '2026-09-30T10:00:00Z'),
      romm('d.zip', 'freegosy', '2026-09-29T10:00:00Z'),
    ]));
    expect(c.romm.map((g) => g.newest.fileName), ['a.zip', 'b.srm']);
    expect(c.romm.first.older.map((e) => e.fileName), ['c.zip', 'd.zip']);
    expect(c.romm.first.tag, 'freegosy');
    expect(c.rommOffline, isFalse);
  });

  test('saves on this PC come newest first; all holds every row', () async {
    final c = await loadSaveCatalog(game, '/roms/mk.z64', _Sources(
      local: [local('retroarch', DateTime(2026, 9, 30)), local('ares', DateTime(2026, 10, 1))],
      backupRows: [SaveEntry(source: SaveSource.backup, fileName: 'b.zip', savedAt: DateTime(2026, 9, 29))],
      romm: [romm('a.zip', 'freegosy', '2026-10-01T07:56:29Z')],
    ));
    expect(c.thisPc.map((e) => e.fileName), ['ares', 'retroarch']);
    expect(c.backups.single.fileName, 'b.zip');
    expect(c.all, hasLength(4));
  });

  test('RomM offline or failing: no RomM rows, and it says so', () async {
    final c = await loadSaveCatalog(game, '/roms/mk.z64', _Sources(local: [local('ares', DateTime(2026, 10, 1))], romm: null));
    expect(c.rommOffline, isTrue);
    expect(c.romm, isEmpty);
    expect(c.thisPc, hasLength(1));
  });

  test('an empty RomM list is not offline', () async {
    final c = await loadSaveCatalog(game, '/roms/mk.z64', _Sources(romm: const []));
    expect(c.rommOffline, isFalse);
  });

  test('save states listed among RomM saves are left out (they have their own tab)', () async {
    final c = await loadSaveCatalog(game, '/roms/mk.z64', _Sources(romm: [
      romm('mk.state1', 'mupen64plus_next', '2026-10-01T07:00:00Z'),
      romm('mk.srm', 'mupen64plus_next', '2026-09-30T07:00:00Z'),
    ]));
    expect(c.romm.single.newest.fileName, 'mk.srm');
  });
}
