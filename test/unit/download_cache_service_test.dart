import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/storage/download_cache_service.dart';

void main() {
  group('DownloadCacheService', () {
    late DownloadCacheService cache;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      cache = DownloadCacheService(prefs);
    });

    test('load - null JSON string is no-op', () {
      cache.load();
      expect(cache.filesByPlatform, isEmpty);
    });

    test('load - corrupt JSON is no-op', () async {
      SharedPreferences.setMockInitialValues({
        'downloaded_files_v2': '{{{{invalid json',
      });
      final prefs = await SharedPreferences.getInstance();
      final corruptCache = DownloadCacheService(prefs);
      corruptCache.load();
      expect(corruptCache.filesByPlatform, isEmpty);
    });

    test('addFile then isDownloaded returns true', () {
      cache.addFile('game.iso', platformSlug: 'ps2');
      expect(cache.isDownloaded('game.iso'), isTrue);
    });

    test('isDownloaded(null) returns false', () {
      expect(cache.isDownloaded(null), isFalse);
    });

    test('isDownloaded("") returns false', () {
      expect(cache.isDownloaded(''), isFalse);
    });

    test('removeFile then isDownloaded returns false', () {
      cache.addFile('game.iso');
      expect(cache.isDownloaded('game.iso'), isTrue);
      cache.removeFile('game.iso');
      expect(cache.isDownloaded('game.iso'), isFalse);
    });

    test('rescanFromDirectory with empty set clears cache', () {
      cache.addFile('game.iso');
      cache.rescanFromDirectory({});
      expect(cache.isDownloaded('game.iso'), isFalse);
    });

    test('addFile with custom platformSlug', () {
      cache.addFile('x.nsp', platformSlug: 'switch');
      expect(cache.filesByPlatform['switch'], contains('x.nsp'));
    });

    test('isDownloaded is case-insensitive', () {
      cache.addFile('Game.ISO');
      expect(cache.isDownloaded('game.iso'), isTrue);
      expect(cache.isDownloaded('GAME.ISO'), isTrue);
    });

    test('rescanFromPlatformMap replaces cache', () {
      cache.addFile('old.iso');
      cache.rescanFromPlatformMap({
        'ps2': {'new.iso'},
      });
      expect(cache.isDownloaded('old.iso'), isFalse);
      expect(cache.isDownloaded('new.iso'), isTrue);
    });

    test('load - valid JSON round-trip', () async {
      cache.addFile('game.iso', platformSlug: 'ps2');
      // Simulate persistence by creating new instance with stored value
      final prefs = await SharedPreferences.getInstance();
      final storedJson = prefs.getString('downloaded_files_v2');
      expect(storedJson, isNotNull);

      SharedPreferences.setMockInitialValues({
        'downloaded_files_v2': storedJson!,
      });
      final freshPrefs = await SharedPreferences.getInstance();
      final freshCache = DownloadCacheService(freshPrefs);
      freshCache.load();
      expect(freshCache.isDownloaded('game.iso'), isTrue);
    });

    test('removeFile from multiple platforms', () {
      cache.addFile('shared.iso', platformSlug: 'ps2');
      cache.addFile('shared.iso', platformSlug: 'psx');
      cache.removeFile('shared.iso');
      expect(cache.isDownloaded('shared.iso'), isFalse);
    });
  });
}
