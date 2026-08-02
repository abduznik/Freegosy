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
        // Real DuckStation PerGameTitle naming: {title}_{slot}.mcd
        final gameSave = File(p.join(memcardsDir.path, 'Suikoden II_1.mcd'));
        await gameSave.writeAsBytes(List.filled(150, 1));

        // Shared cards also exist but per-game card must win.
        await File(p.join(memcardsDir.path, 'shared_card_1.mcd')).writeAsBytes(List.filled(150, 2));

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
        expect(p.basename(files.first.path), 'Suikoden II_1.mcd');
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('falls back to shared_card_N.mcd when no per-game card matches', () async {
      final base = await Directory.systemTemp.createTemp('duckstation_shared');
      try {
        final memcardsDir = Directory(p.join(base.path, 'memcards'));
        await memcardsDir.create(recursive: true);
        // Real DuckStation shared card naming: shared_card_{N}.mcd
        await File(p.join(memcardsDir.path, 'shared_card_1.mcd')).writeAsBytes(List.filled(150, 1));
        await File(p.join(memcardsDir.path, 'shared_card_2.mcd')).writeAsBytes(List.filled(150, 2));

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
            containsAll(['shared_card_1.mcd', 'shared_card_2.mcd']));
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('falls back to legacy Mcd001.mcd style cards too', () async {
      final base = await Directory.systemTemp.createTemp('duckstation_legacy_shared');
      try {
        final memcardsDir = Directory(p.join(base.path, 'memcards'));
        await memcardsDir.create(recursive: true);
        // Old/forks may still use Mcd001.mcd naming.
        await File(p.join(memcardsDir.path, 'Mcd001.mcd')).writeAsBytes(List.filled(150, 1));

        final ds = await _StubDirectoryService.create(
          exePath: null,
          appSupport: base.path,
        );
        final strategy = DuckstationSaveStrategy(
          ds,
          platform: const PlatformInfo('linux', environment: {'HOME': ''}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g4', name: 'Another Random Game.bin', platformSlug: 'ps1', fileSize: 0),
          p.join(base.path, 'Another Random Game.bin'),
        );

        expect(files, hasLength(1));
        expect(p.basename(files.first.path), 'Mcd001.mcd');
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

    test('matches per-game card for multi-disc .m3u with region tags (issue #62)', () async {
      final base = await Directory.systemTemp.createTemp('duckstation_multidisc');
      try {
        final memcardsDir = Directory(p.join(base.path, 'memcards'));
        await memcardsDir.create(recursive: true);
        // DuckStation PerGameTitle card uses the bare disc-set title, while
        // RomM exposes the multidisc ROM as "Final Fantasy VII (USA).m3u".
        await File(p.join(memcardsDir.path, 'Final Fantasy VII_1.mcd'))
            .writeAsBytes(List.filled(150, 1));

        final ds = await _StubDirectoryService.create(
          exePath: null,
          appSupport: base.path,
        );
        final strategy = DuckstationSaveStrategy(
          ds,
          platform: const PlatformInfo('linux', environment: {'HOME': ''}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g5', name: 'Final Fantasy VII (USA).m3u', platformSlug: 'ps1', fileSize: 0),
          p.join(base.path, 'Final Fantasy VII (USA).m3u'),
        );

        expect(files, hasLength(1));
        expect(p.basename(files.first.path), 'Final Fantasy VII_1.mcd');
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('does not match per-game card when region tag differs (no false positive)', () async {
      final base = await Directory.systemTemp.createTemp('duckstation_region_mismatch');
      try {
        final memcardsDir = Directory(p.join(base.path, 'memcards'));
        await memcardsDir.create(recursive: true);
        // Card for a different game in the same series.
        await File(p.join(memcardsDir.path, 'Final Fantasy VIII_1.mcd'))
            .writeAsBytes(List.filled(150, 1));

        final ds = await _StubDirectoryService.create(
          exePath: null,
          appSupport: base.path,
        );
        final strategy = DuckstationSaveStrategy(
          ds,
          platform: const PlatformInfo('linux', environment: {'HOME': ''}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g6', name: 'Final Fantasy VII (USA).m3u', platformSlug: 'ps1', fileSize: 0),
          p.join(base.path, 'Final Fantasy VII (USA).m3u'),
        );

        expect(files, isEmpty);
      } finally {
        await base.delete(recursive: true);
      }
    });
  });

  group('DuckstationSaveStrategy portable mode via settings.ini (scoop)', () {
    test('treats install as portable when settings.ini sits next to exe', () async {
      final base = await Directory.systemTemp.createTemp('duckstation_scoop');
      try {
        final exeDir = p.join(base.path, 'duckstation');
        await Directory(p.join(exeDir, 'memcards')).create(recursive: true);
        await Directory(p.join(exeDir, 'savestates')).create(recursive: true);
        // Scoop/portable builds have settings.ini but NOT portable.txt.
        await File(p.join(exeDir, 'settings.ini')).writeAsString('[Core]\n');
        await File(p.join(exeDir, 'memcards', 'shared_card_1.mcd')).writeAsBytes(List.filled(150, 1));
        final fakeExe = p.join(exeDir, 'duckstation-qt-x64-ReleaseLTCG.exe');
        await File(fakeExe).writeAsString('');

        // LocalAppData is empty — only the exe-dir (portable) layout has saves.
        final emptyLocal = p.join(base.path, 'empty');
        final ds = await _StubDirectoryService.create(exePath: fakeExe, appSupport: '/nonexistent');
        final strategy = DuckstationSaveStrategy(
          ds,
          platform: PlatformInfo('windows', environment: {'LOCALAPPDATA': emptyLocal}),
        );

        final saveDir = await strategy.getSaveDir(
          Game(id: 'g_scoop', name: 'Suikoden II.bin', platformSlug: 'ps1', fileSize: 0),
          '/roms/ps1/Suikoden II.bin',
        );
        expect(saveDir, p.join(exeDir, 'memcards'),
            reason: 'settings.ini next to exe should trigger portable mode');

        final files = await strategy.getSaveFiles(
          Game(id: 'g_scoop', name: 'Suikoden II.bin', platformSlug: 'ps1', fileSize: 0),
          '/roms/ps1/Suikoden II.bin',
        );
        expect(files, hasLength(1));
        expect(p.basename(files.first.path), 'shared_card_1.mcd');
      } finally {
        await base.delete(recursive: true);
      }
    });
  });

  group('SaveStrategy.normalizeSaveMatchName', () {
    test('strips region/version tags and collapses whitespace', () async {
      final ds = await _StubDirectoryService.create(exePath: null, appSupport: '');
      final strategy = DuckstationSaveStrategy(
        ds,
        platform: const PlatformInfo('linux', environment: {'HOME': ''}),
      );

      expect(strategy.normalizeSaveMatchName('Final Fantasy VII (USA)'), 'Final Fantasy VII');
      expect(strategy.normalizeSaveMatchName('Suikoden II [Rev 1]'), 'Suikoden II');
      expect(strategy.normalizeSaveMatchName('Game (USA) (En,Fr)'), 'Game');
      expect(strategy.normalizeSaveMatchName('  spaced   name  '), 'spaced name');
      expect(strategy.normalizeSaveMatchName('Trailing---'), 'Trailing');
    });
  });
}
