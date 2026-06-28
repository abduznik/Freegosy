import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('RommService URL and auth methods', () {
    late RommService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      final config = RomMConfig(
        baseUrl: 'https://romm.example.com',
        username: 'user',
        password: 'pass',
        apiKey: 'test-api-key',
        token: 'test-token',
      );
      service = RommService(config);
    });

    group('getDownloadUrl', () {
      test('encodes special characters', () {
        final game = Game(
          id: '1',
          name: "Crash Bandicoot (USA)",
          fileName: "Crash Bandicoot (USA).iso",
          fileSize: 1000,
        );
        final url = service.getDownloadUrl(game);
        expect(url, contains('%28'));
        expect(url, contains('%29'));
        expect(url, contains('Crash'));
      });

      test('truncates long filenames', () {
        final longName = '${'A' * 200}.iso';
        final game = Game(
          id: '2',
          name: 'Test Game',
          fileName: longName,
          fileSize: 1000,
        );
        final url = service.getDownloadUrl(game);
        // Should be truncated to ~50 chars + extension
        expect(url.length, lessThan(200));
        expect(url, contains('.iso'));
      });

      test('uses fileUrl override when set', () {
        final game = Game(
          id: '3',
          name: 'Test',
          fileUrl: 'https://cdn.example.com/game.iso',
          fileSize: 1000,
        );
        final url = service.getDownloadUrl(game);
        expect(url, 'https://cdn.example.com/game.iso');
      });

      test('constructs URL from game id and filename', () {
        final game = Game(
          id: '42',
          name: 'Test Game',
          fileName: 'game.iso',
          fileSize: 1000,
        );
        final url = service.getDownloadUrl(game);
        expect(url, contains('/api/roms/42/content/'));
        expect(url, contains('game.iso'));
      });
    });

    group('resolveCoverUrl', () {
      test('protocol-relative URL gets https prefix', () {
        final game = Game(
          id: '1',
          name: 'Test',
          urlCover: '//cdn.example.com/cover.jpg',
          fileSize: 0,
        );
        final url = service.resolveCoverUrl(game);
        expect(url, 'https://cdn.example.com/cover.jpg');
      });

      test('absolute http URL returned as-is', () {
        final game = Game(
          id: '1',
          name: 'Test',
          pathCoverLarge: 'https://host/cover.jpg',
          fileSize: 0,
        );
        final url = service.resolveCoverUrl(game);
        expect(url, 'https://host/cover.jpg');
      });

      test('relative path gets host prepended', () {
        final game = Game(
          id: '1',
          name: 'Test',
          pathCoverLarge: '/assets/cover.jpg',
          fileSize: 0,
        );
        final url = service.resolveCoverUrl(game);
        expect(url, 'https://romm.example.com/assets/cover.jpg');
      });

      test('all null paths returns null', () {
        final game = Game(id: '1', name: 'Test', fileSize: 0);
        final url = service.resolveCoverUrl(game);
        expect(url, isNull);
      });
    });

    group('authHeader', () {
      test('apiKey has highest priority', () {
        expect(service.authHeader, 'Bearer test-api-key');
      });

      test('token used when apiKey is empty', () {
        final config = RomMConfig(
          baseUrl: 'https://romm.example.com',
          username: 'user',
          password: 'pass',
          token: 'my-token',
        );
        final svc = RommService(config);
        expect(svc.authHeader, 'Bearer my-token');
      });

      test('basic auth used when no key or token', () {
        final config = RomMConfig(
          baseUrl: 'https://romm.example.com',
          username: 'user',
          password: 'pass',
        );
        final svc = RommService(config);
        final expected = 'Basic ${base64Encode(utf8.encode('user:pass'))}';
        expect(svc.authHeader, expected);
      });
    });
  });
}
