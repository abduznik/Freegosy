import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/pcsx2_save_strategy.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal DirectoryService stub — implements only the methods
/// Pcsx2SaveStrategy calls during save resolution.
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
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    return _StubDirectoryService._internal(prefs, exePath: exePath, appSupport: appSupport);
  }

  @override
  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async => _exePath;

  @override
  Future<String> getEmulatorAppSupportDirectory(String emulatorName, {String? platformSlug}) async => _appSupport;
}

void main() {
  group('Pcsx2SaveStrategy getSaveFiles two-layer detection', () {
    test('per-game folder save takes priority over shared memcard', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_folder');
      try {
        // Portable layout: root = exeDir, memcards/ next to exe.
        final exeDir = p.join(base.path, 'pcsx2');
        await Directory(p.join(exeDir, 'memcards')).create(recursive: true);
        await File(p.join(exeDir, 'memcards', 'Mcd001.ps2')).writeAsBytes(List.filled(150, 1));

        // Per-game folder save under saves/{Serial}.
        final perGameDir = Directory(p.join(exeDir, 'saves', 'SCUS-97113'));
        await perGameDir.create(recursive: true);
        await File(p.join(perGameDir.path, 'data.bin')).writeAsBytes(List.filled(150, 2));

        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          platform: const PlatformInfo('windows', environment: {}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g1', name: 'Ico (SCUS-97113)', platformSlug: 'ps2', fileSize: 0),
          p.join(base.path, 'Ico (SCUS-97113).iso'),
        );

        expect(files, hasLength(1));
        expect(files.first.path, contains('SCUS-97113'));
        expect(files.first.path, isNot(contains('Mcd001')));
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('falls back to shared 8MB memcard when no per-game folder exists', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_memcard');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        await Directory(p.join(exeDir, 'memcards')).create(recursive: true);
        final memcard = File(p.join(exeDir, 'memcards', 'Mcd001.ps2'));
        await memcard.writeAsBytes(List.filled(150, 1));

        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          platform: const PlatformInfo('windows', environment: {}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g2', name: 'NoFolder Game', platformSlug: 'ps2', fileSize: 0),
          p.join(base.path, 'NoFolder Game.iso'),
        );

        expect(files, hasLength(1));
        expect(p.basename(files.first.path), 'Mcd001.ps2');
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('serial is extracted from filename when present', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_serial');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        await Directory(p.join(exeDir, 'memcards')).create(recursive: true);
        await File(p.join(exeDir, 'memcards', 'Mcd001.ps2')).writeAsBytes(List.filled(150, 1));
        final perGameDir = Directory(p.join(exeDir, 'saves', 'SLUS-12345'));
        await perGameDir.create(recursive: true);
        await File(p.join(perGameDir.path, 'save.bin')).writeAsBytes(List.filled(150, 2));

        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          platform: const PlatformInfo('windows', environment: {}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g3', name: 'Game (SLUS-12345)', platformSlug: 'ps2', fileSize: 0),
          p.join(base.path, 'Game (SLUS-12345).iso'),
        );

        expect(files, hasLength(1));
        expect(files.first.path, contains('SLUS-12345'));
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('skips timestamped memcard backups like Mcd001 [date].ps2', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_timestamp');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        await Directory(p.join(exeDir, 'memcards')).create(recursive: true);
        await File(p.join(exeDir, 'memcards', 'Mcd001.ps2')).writeAsBytes(List.filled(150, 1));
        await File(p.join(exeDir, 'memcards', 'Mcd001 [2026-04-03_20-31-19].ps2'))
            .writeAsBytes(List.filled(150, 2));

        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          platform: const PlatformInfo('windows', environment: {}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g4', name: 'NoFolder Game', platformSlug: 'ps2', fileSize: 0),
          p.join(base.path, 'NoFolder Game.iso'),
        );

        expect(files, hasLength(1));
        expect(p.basename(files.first.path), 'Mcd001.ps2');
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('detects folder-type memcard (directory named McdXXX.ps2)', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_folder_card');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        // Real PCSX2 "folder memcard": a DIRECTORY named Mcd001.ps2 under memcards/.
        final folderCard = Directory(p.join(exeDir, 'memcards', 'Mcd001.ps2'));
        await folderCard.create(recursive: true);
        await File(p.join(folderCard.path, 'data.bin')).writeAsBytes(List.filled(150, 1));

        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          platform: const PlatformInfo('windows', environment: {}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g5', name: 'FolderCard Game', platformSlug: 'ps2', fileSize: 0),
          p.join(base.path, 'FolderCard Game.iso'),
        );

        expect(files, hasLength(1));
        expect(files.first.path, folderCard.path);
      } finally {
        await base.delete(recursive: true);
      }
    });
  });
}
