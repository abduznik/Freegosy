import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';

void main() {
  group('RommCapabilities', () {
    group('version parsing', () {
      test('parses standard semver', () {
        final caps = RommCapabilities(version: '4.9.0');
        expect(caps.major, 4);
        expect(caps.minor, 9);
      });

      test('parses pre-release version with hyphen', () {
        final caps = RommCapabilities(version: '4.9.0-beta.1');
        expect(caps.major, 4);
        expect(caps.minor, 9);
      });

      test('parses alpha version', () {
        final caps = RommCapabilities(version: '4.9.0-alpha.3');
        expect(caps.major, 4);
        expect(caps.minor, 9);
      });

      test('parses older version correctly', () {
        final caps = RommCapabilities(version: '4.8.1');
        expect(caps.major, 4);
        expect(caps.minor, 8);
      });

      test('unknown() defaults to 0.0.0', () {
        final caps = RommCapabilities.unknown();
        expect(caps.major, 0);
        expect(caps.minor, 0);
        expect(caps.version, '0.0.0');
      });

      test('handles malformed version gracefully', () {
        final caps = RommCapabilities(version: 'dev');
        expect(caps.major, 0);
        expect(caps.minor, 0);
      });
    });

    group('hasDeviceSaveSync', () {
      test('true for 4.9.0', () {
        expect(RommCapabilities(version: '4.9.0').hasDeviceSaveSync, isTrue);
      });

      test('true for 4.9.0-beta.1', () {
        expect(RommCapabilities(version: '4.9.0-beta.1').hasDeviceSaveSync, isTrue);
      });

      test('true for 5.0.0', () {
        expect(RommCapabilities(version: '5.0.0').hasDeviceSaveSync, isTrue);
      });

      test('false for 4.8.1', () {
        expect(RommCapabilities(version: '4.8.1').hasDeviceSaveSync, isFalse);
      });

      test('false for 4.8.0', () {
        expect(RommCapabilities(version: '4.8.0').hasDeviceSaveSync, isFalse);
      });

      test('false for 3.9.0', () {
        expect(RommCapabilities(version: '3.9.0').hasDeviceSaveSync, isFalse);
      });

      test('false for unknown', () {
        expect(RommCapabilities.unknown().hasDeviceSaveSync, isFalse);
      });
    });

    group('derived flags', () {
      test('hasPlaySessionTracking matches hasDeviceSaveSync', () {
        final caps49 = RommCapabilities(version: '4.9.0');
        expect(caps49.hasPlaySessionTracking, caps49.hasDeviceSaveSync);

        final caps48 = RommCapabilities(version: '4.8.1');
        expect(caps48.hasPlaySessionTracking, caps48.hasDeviceSaveSync);
      });

      test('hasSaveSummary matches hasDeviceSaveSync', () {
        final caps = RommCapabilities(version: '4.9.0');
        expect(caps.hasSaveSummary, caps.hasDeviceSaveSync);
      });
    });

    group('toString', () {
      test('includes version and flag', () {
        final caps = RommCapabilities(version: '4.9.0');
        expect(caps.toString(), contains('4.9.0'));
        expect(caps.toString(), contains('deviceSync=true'));
      });

      test('shows false for legacy version', () {
        final caps = RommCapabilities(version: '4.8.1');
        expect(caps.toString(), contains('deviceSync=false'));
      });
    });
  });

  group('DeviceSync', () {
    test('fromJson parses all fields', () {
      final json = {
        'device_id': 'abc-123',
        'device_name': 'My Steam Deck',
        'last_synced_at': '2026-06-06T10:00:00Z',
        'is_untracked': false,
        'is_current': true,
      };
      final sync = DeviceSync.fromJson(json);
      expect(sync.deviceId, 'abc-123');
      expect(sync.deviceName, 'My Steam Deck');
      expect(sync.lastSyncedAt, DateTime.parse('2026-06-06T10:00:00Z'));
      expect(sync.isUntracked, isFalse);
      expect(sync.isCurrent, isTrue);
    });

    test('fromJson handles missing optional fields', () {
      final json = {'device_id': 'abc-123'};
      final sync = DeviceSync.fromJson(json);
      expect(sync.deviceId, 'abc-123');
      expect(sync.deviceName, isNull);
      expect(sync.lastSyncedAt, isNull);
      expect(sync.isUntracked, isFalse);
      expect(sync.isCurrent, isFalse);
    });

    test('fromJson parses is_current=false correctly', () {
      final json = {
        'device_id': 'abc-123',
        'is_current': false,
        'is_untracked': false,
      };
      final sync = DeviceSync.fromJson(json);
      expect(sync.isCurrent, isFalse);
    });
  });

  group('SaveFile with 4.9 fields', () {
    test('fromJson parses slot', () {
      final json = {
        'id': '1',
        'rom_id': '42',
        'download_path': '/api/saves/1/content',
        'slot': 'Main Playthrough',
        'device_syncs': [],
      };
      final save = SaveFile.fromJson(json);
      expect(save.slot, 'Main Playthrough');
      expect(save.deviceSyncs, isEmpty);
    });

    test('fromJson parses device_syncs', () {
      final json = {
        'id': '1',
        'rom_id': '42',
        'download_path': '/api/saves/1/content',
        'slot': null,
        'device_syncs': [
          {
            'device_id': 'abc-123',
            'device_name': 'Freegosy on windows',
            'last_synced_at': '2026-06-06T10:00:00Z',
            'is_untracked': false,
            'is_current': true,
          },
        ],
      };
      final save = SaveFile.fromJson(json);
      expect(save.deviceSyncs.length, 1);
      expect(save.deviceSyncs.first.deviceId, 'abc-123');
      expect(save.deviceSyncs.first.isCurrent, isTrue);
    });

    test('fromJson defaults to empty deviceSyncs when missing', () {
      final json = {
        'id': '1',
        'rom_id': '42',
        'download_path': '/api/saves/1/content',
      };
      final save = SaveFile.fromJson(json);
      expect(save.deviceSyncs, isEmpty);
      expect(save.slot, isNull);
    });

    test('fromJson prefers download_path over url', () {
      final json = {
        'id': '1',
        'rom_id': '42',
        'download_path': '/api/saves/1/content',
        'url': '/old/url',
      };
      final save = SaveFile.fromJson(json);
      expect(save.url, '/api/saves/1/content');
    });
  });
}
