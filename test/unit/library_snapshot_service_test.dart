import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/library_snapshot_service.dart';

void main() {
  group('LibrarySnapshotService', () {
    late LibrarySnapshotService service;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('snapshot_test_');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      service = LibrarySnapshotService();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('savePlatforms then loadPlatforms round-trip', () async {
      final platforms = [
        Platform(id: 1, name: 'PlayStation 2', slug: 'ps2'),
        Platform(id: 2, name: 'Game Boy Advance', slug: 'gba'),
      ];

      await service.savePlatforms(platforms);
      final loaded = await service.loadPlatforms();

      expect(loaded.length, 2);
      expect(loaded[0].name, 'PlayStation 2');
      expect(loaded[0].slug, 'ps2');
      expect(loaded[1].name, 'Game Boy Advance');
      expect(loaded[1].slug, 'gba');
    });

    test('loadPlatforms when file does not exist returns empty', () async {
      final loaded = await service.loadPlatforms();
      expect(loaded, isEmpty);
    });

    test('loadPlatforms with corrupt JSON returns empty', () async {
      final file = File('${tempDir.path}/platforms_snapshot.json');
      await file.writeAsString('{{{{not valid json');

      final loaded = await service.loadPlatforms();
      expect(loaded, isEmpty);
    });

    test('saveCollections then loadCollections round-trip', () async {
      final collections = [
        {'id': 1, 'name': 'Favorites'},
        {'id': 2, 'name': 'RPGs'},
      ];

      await service.saveCollections(collections);
      final loaded = await service.loadCollections();

      expect(loaded.length, 2);
      expect(loaded[0]['name'], 'Favorites');
      expect(loaded[1]['name'], 'RPGs');
    });

    test('clear then loadPlatforms returns empty', () async {
      final platforms = [
        Platform(id: 1, name: 'PS2', slug: 'ps2'),
      ];
      await service.savePlatforms(platforms);
      expect((await service.loadPlatforms()).length, 1);

      await service.clear();
      final loaded = await service.loadPlatforms();
      expect(loaded, isEmpty);
    });

    test('clear when files do not exist is no-op', () async {
      // Should not throw
      await service.clear();
      final loaded = await service.loadPlatforms();
      expect(loaded, isEmpty);
    });

    test('loadCollections with corrupt JSON returns empty', () async {
      final file = File('${tempDir.path}/collections_snapshot.json');
      await file.writeAsString('{bad json}');

      final loaded = await service.loadCollections();
      expect(loaded, isEmpty);
    });

    test('loadCollections when file does not exist returns empty', () async {
      final loaded = await service.loadCollections();
      expect(loaded, isEmpty);
    });
  });
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String _path;
  _FakePathProvider(this._path);

  @override
  Future<String?> getApplicationSupportPath() async => _path;
}
