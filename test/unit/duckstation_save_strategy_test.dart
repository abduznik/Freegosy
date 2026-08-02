import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/duckstation_save_strategy.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal DirectoryService stub — implements only the methods
/// DuckstationSaveStrategy calls during save resolution.
class _StubDirectoryService extends DirectoryService {
  final String? _exePath;
  final String _appSupport;

  _StubDirectoryService._internal(
    super.prefs, {
    required String? exePath,
    required String appSupport,
  })  : _exePath = exePath,
        _appSupport = appSupport;

  static Future<_StubDirectoryService> create({
    String? exePath,
    String appSupport = '',
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return _StubDirectoryService._internal(prefs, exePath: exePath, appSupport: appSupport);
  }

  @override
  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async => _exePath;

  @override
  Future<String> getEmulatorAppSupportDirectory(String emulatorName, {String? platformSlug}) async => _appSupport;
}

void main() {
  group('DuckstationSaveStrategy getSaveFiles two-layer detection', () {
    test('returns per-game .mcd when it matches the ROM stem', () async {
      final base = await Directory.systemTemp.createTemp('duckstation_stem');
      try {
        final memcardsDir = Directory(p.join(base.path, 'memcards'));
        await memcardsDir.create(recursive: true);
        final gameSave = File(p.join(memcardsDir.path, 'Suikoden II.mcd'));
        await gameSave.writeAsBytes(List.filled(150, 1));

        // Shared cards also exist but per-game card must win.
        await File(p.join(memcardsDir.path, 'Mcd001.mcd')).writeAsBytes(List.filled(150, 2));

        final ds = await _StubDirectoryService.create(
          exePath: null,
          appSupport: base.path,
        );
        final strategy = DuckstationSaveStrategy(
          ds,
          platform: const PlatformInfo('linux', environment: {'HOME': ''}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g1', name: 'Suikoden II.m3u', platformSlug: 'ps1', fileSize: 0),
          p.join(base.path, 'Suikoden II.m3u'),
        );

        expect(files, hasLength(1));
        expect(p.basename(files.first.path), 'Suikoden II.mcd');
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('falls back to shared Mcd001/Mcd002.mcd when no per-game card matches', () async {
      final base = await Directory.systemTemp.createTemp('duckstation_shared');
      try {
        final memcardsDir = Directory(p.join(base.path, 'memcards'));
        await memcardsDir.create(recursive: true);
        await File(p.join(memcardsDir.path, 'Mcd001.mcd')).writeAsBytes(List.filled(150, 1));
        await File(p.join(memcardsDir.path, 'Mcd002.mcd')).writeAsBytes(List.filled(150, 2));

        // No .mcd matching the game name — only shared cards.
        final ds = await _StubDirectoryService.create(
          exePath: null,
          appSupport: base.path,
        );
        final strategy = DuckstationSaveStrategy(
          ds,
          platform: const PlatformInfo('linux', environment: {'HOME': ''}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g2', name: 'Some Random Game.bin', platformSlug: 'ps1', fileSize: 0),
          p.join(base.path, 'Some Random Game.bin'),
        );

        expect(files, hasLength(2));
        expect(files.map((f) => p.basename(f.path)).toSet(),
            containsAll(['Mcd001.mcd', 'Mcd002.mcd']));
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('returns empty list when memcards dir is missing', () async {
      final base = await Directory.systemTemp.createTemp('duckstation_empty');
      try {
        final ds = await _StubDirectoryService.create(
          exePath: null,
          appSupport: base.path,
        );
        final strategy = DuckstationSaveStrategy(
          ds,
          platform: const PlatformInfo('linux', environment: {'HOME': ''}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g3', name: 'No Saves Yet.bin', platformSlug: 'ps1', fileSize: 0),
          p.join(base.path, 'No Saves Yet.bin'),
        );

        expect(files, isEmpty);
      } finally {
        await base.delete(recursive: true);
      }
    });
  });
}
