import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/pcsx2_save_strategy.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Reuses the mock SharedPreferences backend a preceding
/// `_StubDirectoryService.create()` call already initialized in the same
/// test — Pcsx2SaveStrategy's own AppPreferences is unrelated to
/// DirectoryService's, but there's no need for a second mock store.
Future<SharedPreferencesAppPreferences> _testPrefs() async =>
    SharedPreferencesAppPreferences(await SharedPreferences.getInstance());

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
          await _testPrefs(),
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
          await _testPrefs(),
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
          await _testPrefs(),
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
          await _testPrefs(),
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
          await _testPrefs(),
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

    test('bundles only the matching artifact folder inside a multi-game folder memcard, not the whole card', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_multi_game_card');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        final folderCard = Directory(p.join(exeDir, 'memcards', 'Mcd001.ps2'));
        // Real PCSX2 folder names: <region-prefix><dash-serial><suffix>.
        final matching = Directory(p.join(folderCard.path, 'BASLUS-20152AC04'));
        final other = Directory(p.join(folderCard.path, 'BASCUS-97113AC04'));
        await matching.create(recursive: true);
        await other.create(recursive: true);
        await File(p.join(matching.path, 'save.bin')).writeAsBytes(List.filled(150, 1));
        await File(p.join(other.path, 'save.bin')).writeAsBytes(List.filled(150, 2));

        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g6', name: 'Game (SLUS-20152)', platformSlug: 'ps2', fileSize: 0),
          p.join(base.path, 'Game (SLUS-20152).iso'),
        );

        // Only the matching artifact folder — not the unrelated game's
        // folder, not the whole shared card.
        expect(files, hasLength(1));
        expect(files.first.path, matching.path);
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('detects a change made only inside a matching artifact folder even when the card directory itself is untouched', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_stale_card_mtime');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        final folderCard = Directory(p.join(exeDir, 'memcards', 'Mcd001.ps2'));
        final matching = Directory(p.join(folderCard.path, 'BASLUS-21693'));
        await matching.create(recursive: true);
        final saveFile = File(p.join(matching.path, 'save.dat'));
        await saveFile.writeAsBytes(List.filled(64, 1));

        // The card directory now exists with its artifact folder already in
        // place — mark this as "before the session" and give the filesystem
        // a moment so mtime comparisons below aren't sub-resolution flaky.
        await Future.delayed(const Duration(seconds: 1));
        final sessionStart = DateTime.now();
        await Future.delayed(const Duration(seconds: 1));

        // Rewrite the existing save file in place, exactly as PCSX2 does.
        // This updates the file's own mtime but adds/removes no entries
        // from the card directory, so the card's own mtime stays untouched.
        await saveFile.writeAsBytes(List.filled(64, 2));

        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g16', name: 'Game (SLUS-21693)', platformSlug: 'ps2', fileSize: 0),
          p.join(base.path, 'Game (SLUS-21693).iso'),
          sessionStart: sessionStart,
        );

        expect(files, hasLength(1));
        expect(files.first.path, matching.path);
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('matches a real dash-separated suffix folder (e.g. "-PROFILE") seen on an actual PCSX2 card', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_dash_suffix_match');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        final folderCard = Directory(p.join(exeDir, 'memcards', 'Mcd001.ps2'));
        final matching = Directory(p.join(folderCard.path, 'BASLUS-21026-PROFILE'));
        await matching.create(recursive: true);
        await File(p.join(matching.path, 'save.dat')).writeAsBytes(List.filled(64, 1));

        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g14', name: 'Game (SLUS-21026)', platformSlug: 'ps2', fileSize: 0),
          p.join(base.path, 'Game (SLUS-21026).iso'),
        );

        expect(files, hasLength(1));
        expect(files.first.path, matching.path);
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('bundles every sibling artifact folder sharing this game\'s serial (data + system config)', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_sibling_artifacts');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        final folderCard = Directory(p.join(exeDir, 'memcards', 'Mcd001.ps2'));
        final data = Directory(p.join(folderCard.path, 'BASLUS-20152AC04'));
        final sys = Directory(p.join(folderCard.path, 'BASLUS-20152SYS'));
        final other = Directory(p.join(folderCard.path, 'BASCUS-97113AC04'));
        await data.create(recursive: true);
        await sys.create(recursive: true);
        await other.create(recursive: true);
        await File(p.join(data.path, 'icon.sys')).writeAsBytes(List.filled(64, 1));
        await File(p.join(sys.path, 'config.dat')).writeAsBytes(List.filled(64, 2));
        await File(p.join(other.path, 'save.bin')).writeAsBytes(List.filled(64, 3));

        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g10', name: 'Game (SLUS-20152)', platformSlug: 'ps2', fileSize: 0),
          p.join(base.path, 'Game (SLUS-20152).iso'),
        );

        expect(files, hasLength(2));
        final paths = files.map((f) => f.path).toSet();
        expect(paths, {data.path, sys.path});
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('skips a folder-type memcard entirely when it contains no matching serial folder', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_no_match_card');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        final folderCard = Directory(p.join(exeDir, 'memcards', 'Mcd001.ps2'));
        await Directory(p.join(folderCard.path, 'BASCUS-97113AC04')).create(recursive: true);
        await File(p.join(folderCard.path, 'BASCUS-97113AC04', 'save.bin'))
            .writeAsBytes(List.filled(150, 2));

        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g7', name: 'Game (SLUS-20152)', platformSlug: 'ps2', fileSize: 0),
          p.join(base.path, 'Game (SLUS-20152).iso'),
        );

        expect(files, isEmpty);
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('folder-type memcard bundle survives a push (zip) then restore round trip, without dragging along other games', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_folder_round_trip');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        final folderCard = Directory(p.join(exeDir, 'memcards', 'Mcd001.ps2'));
        final matching = Directory(p.join(folderCard.path, 'BASLUS-20152AC04'));
        final other = Directory(p.join(folderCard.path, 'BASCUS-97113AC04'));
        await matching.create(recursive: true);
        await other.create(recursive: true);
        await File(p.join(matching.path, 'save.bin')).writeAsBytes(List.filled(150, 1));
        await File(p.join(other.path, 'save.bin')).writeAsBytes(List.filled(150, 2));

        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        final files = await strategy.getSaveFiles(
          Game(id: 'g6', name: 'Game (SLUS-20152)', platformSlug: 'ps2', fileSize: 0),
          p.join(base.path, 'Game (SLUS-20152).iso'),
        );
        expect(files, hasLength(1));

        // Zip it exactly the way SaveSyncService's push path does — no card
        // wrapper at all, since only the matching artifact folder is bundled.
        final zipPath = p.join(base.path, 'push.zip');
        final encoder = ZipFileEncoder();
        encoder.create(zipPath);
        await encoder.addDirectory(Directory(files.first.path), includeDirName: true);
        encoder.close();
        final zipBytes = await File(zipPath).readAsBytes();

        // Wipe the card back to empty (but keep it existing, as it would be
        // on a real install), as if restoring this one save onto a card that
        // doesn't have it yet.
        await folderCard.delete(recursive: true);
        await folderCard.create(recursive: true);

        final ok = await strategy.restoreSave(
          Game(id: 'g6', name: 'Game (SLUS-20152)', platformSlug: 'ps2', fileSize: 0),
          exeDir,
          zipBytes,
          'push.zip',
        );
        expect(ok, isTrue);

        final restoredMatch = File(p.join(matching.path, 'save.bin'));
        expect(await restoredMatch.exists(), isTrue,
            reason: 'expected restored file at ${restoredMatch.path}');

        // The unrelated game's data was never uploaded in the first place —
        // this is the whole point of narrowing the bundle — so it must not
        // reappear after restore either.
        expect(await other.exists(), isFalse);

        // Must NOT have been misfiled as a save state.
        final wrongFile = File(p.join(exeDir, 'sstates', 'save.bin'));
        expect(await wrongFile.exists(), isFalse);
      } finally {
        await base.delete(recursive: true);
      }
    });
  });

  group('Pcsx2SaveStrategy restoreSave zip entry-shape handling', () {
    Future<Uint8List> buildZip(Map<String, List<int>> entries) async {
      final archive = Archive();
      for (final e in entries.entries) {
        archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
      }
      final bytes = ZipEncoder().encode(archive);
      return Uint8List.fromList(bytes);
    }

    test('folder-type memcard bundle (Mcd001.ps2/<serial>/<file>) restores under memcards/, not sstates/', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_restore_folder_memcard');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        await Directory(p.join(exeDir, 'memcards')).create(recursive: true);
        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        final zipBytes = await buildZip({
          'Mcd001.ps2/BASLUS-12345/some_save_file': List.filled(64, 7),
        });

        final ok = await strategy.restoreSave(
          Game(id: 'g6', name: 'FolderMemcard Game', platformSlug: 'ps2', fileSize: 0),
          exeDir,
          zipBytes,
          'FolderMemcard Game.zip',
        );

        expect(ok, isTrue);

        final expectedFile = File(p.join(
            exeDir, 'memcards', 'Mcd001.ps2', 'BASLUS-12345', 'some_save_file'));
        expect(await expectedFile.exists(), isTrue,
            reason: 'expected restored file at ${expectedFile.path}');

        final wrongFile = File(p.join(exeDir, 'sstates', 'some_save_file'));
        expect(await wrongFile.exists(), isFalse,
            reason: 'folder-type memcard entries must not land in sstates/');
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('bare serial-folder save (SLUS-12345/file) still restores under saves/{Serial}/', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_restore_serial');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        await Directory(p.join(exeDir, 'memcards')).create(recursive: true);
        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        final zipBytes = await buildZip({
          'SLUS-12345/save.bin': List.filled(64, 3),
        });

        final ok = await strategy.restoreSave(
          Game(id: 'g7', name: 'Serial Game', platformSlug: 'ps2', fileSize: 0),
          exeDir,
          zipBytes,
          'Serial Game.zip',
        );

        expect(ok, isTrue);
        final expectedFile =
            File(p.join(exeDir, 'saves', 'SLUS-12345', 'save.bin'));
        expect(await expectedFile.exists(), isTrue);
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('flat shared memcard file (Mcd001.ps2) still restores under memcards/', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_restore_flat');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        await Directory(p.join(exeDir, 'memcards')).create(recursive: true);
        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        final zipBytes = await buildZip({
          'Mcd001.ps2': List.filled(64, 9),
        });

        final ok = await strategy.restoreSave(
          Game(id: 'g8', name: 'FlatMemcard Game', platformSlug: 'ps2', fileSize: 0),
          exeDir,
          zipBytes,
          'FlatMemcard Game.zip',
        );

        expect(ok, isTrue);
        final expectedFile = File(p.join(exeDir, 'memcards', 'Mcd001.ps2'));
        expect(await expectedFile.exists(), isTrue);
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('folder-type memcard bundle from a non-Mcd-named card (e.g. Argosy) restores by superblock detection', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_restore_superblock_card');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        // An existing local folder-type memcard, as PCSX2 itself created it.
        await Directory(p.join(exeDir, 'memcards', 'Mcd001.ps2')).create(recursive: true);
        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        // Argosy identifies a card by its _pcsx2_superblock file rather than
        // by name, so its uploaded card folder can be called anything.
        final zipBytes = await buildZip({
          'test/_pcsx2_superblock': List.filled(8, 1),
          'test/BASLUS-20152AC04/icon.sys': List.filled(64, 2),
        });

        final ok = await strategy.restoreSave(
          Game(id: 'g9', name: 'Argosy Bundle Game', platformSlug: 'ps2', fileSize: 0),
          exeDir,
          zipBytes,
          'Argosy Bundle Game.zip',
        );

        expect(ok, isTrue);
        // Restored under the LOCAL Mcd001.ps2 slot, not a new "test" folder —
        // PCSX2 only recognizes memcard slots by the McdNNN.ps2 convention.
        final expectedSuperblock =
            File(p.join(exeDir, 'memcards', 'Mcd001.ps2', '_pcsx2_superblock'));
        final expectedGameFile = File(
            p.join(exeDir, 'memcards', 'Mcd001.ps2', 'BASLUS-20152AC04', 'icon.sys'));
        expect(await expectedSuperblock.exists(), isTrue);
        expect(await expectedGameFile.exists(), isTrue);
        expect(await Directory(p.join(exeDir, 'memcards', 'test')).exists(), isFalse,
            reason: 'must not create a new folder using the zip\'s own card name');
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('bare artifact folder with no card wrapper at all (narrowed push shape) restores into the existing local slot', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_restore_bare_artifact');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        // An existing local folder-type memcard, as PCSX2 itself created it.
        await Directory(p.join(exeDir, 'memcards', 'Mcd001.ps2')).create(recursive: true);
        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        // No Mcd wrapper, no superblock — exactly what getSaveFiles now
        // uploads for a folder-type memcard save.
        final zipBytes = await buildZip({
          'BASLUS-20152AC04/icon.sys': List.filled(64, 5),
        });

        final ok = await strategy.restoreSave(
          Game(id: 'g11', name: 'Bare Artifact Game', platformSlug: 'ps2', fileSize: 0),
          exeDir,
          zipBytes,
          'Bare Artifact Game.zip',
        );

        expect(ok, isTrue);
        final expectedFile = File(
            p.join(exeDir, 'memcards', 'Mcd001.ps2', 'BASLUS-20152AC04', 'icon.sys'));
        expect(await expectedFile.exists(), isTrue);

        final wrongFile = File(p.join(exeDir, 'sstates', 'icon.sys'));
        expect(await wrongFile.exists(), isFalse);
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('bare artifact folder with a dash-separated suffix (e.g. "-PROFILE") restores intact', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_restore_dash_suffix');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        // Real names seen on an actual PCSX2 folder-memcard: some artifact
        // folders have no suffix, some glue it on ("AC04"), and some use a
        // dash before it ("-PROFILE") — the matcher can't assume a fixed
        // suffix shape.
        await Directory(p.join(exeDir, 'memcards', 'Mcd001.ps2')).create(recursive: true);
        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        final zipBytes = await buildZip({
          'BASLUS-21026-PROFILE/save.dat': List.filled(64, 6),
        });

        final ok = await strategy.restoreSave(
          Game(id: 'g12', name: 'Dash Suffix Game', platformSlug: 'ps2', fileSize: 0),
          exeDir,
          zipBytes,
          'Dash Suffix Game.zip',
        );

        expect(ok, isTrue);
        final expectedFile = File(p.join(
            exeDir, 'memcards', 'Mcd001.ps2', 'BASLUS-21026-PROFILE', 'save.dat'));
        expect(await expectedFile.exists(), isTrue);
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('bare artifact folder with no suffix at all restores intact', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_restore_no_suffix');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        await Directory(p.join(exeDir, 'memcards', 'Mcd001.ps2')).create(recursive: true);
        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        final zipBytes = await buildZip({
          'BASLUS-20502/save.dat': List.filled(64, 7),
        });

        final ok = await strategy.restoreSave(
          Game(id: 'g13', name: 'No Suffix Game', platformSlug: 'ps2', fileSize: 0),
          exeDir,
          zipBytes,
          'No Suffix Game.zip',
        );

        expect(ok, isTrue);
        final expectedFile =
            File(p.join(exeDir, 'memcards', 'Mcd001.ps2', 'BASLUS-20502', 'save.dat'));
        expect(await expectedFile.exists(), isTrue);
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('restoring over an existing save inside a folder-type memcard leaves no .bak files behind', () async {
      final base = await Directory.systemTemp.createTemp('pcsx2_restore_no_bak');
      try {
        final exeDir = p.join(base.path, 'pcsx2');
        final artifactDir =
            Directory(p.join(exeDir, 'memcards', 'Mcd001.ps2', 'BASLUS-20502'));
        await artifactDir.create(recursive: true);
        // A file already exists at the target path — this is exactly what
        // triggers backupSave() to write .bak/.bak1/.bak2 siblings, which
        // PCSX2 itself has been observed to choke on (refuses to save again
        // until they're manually removed) when they land inside a folder-
        // type memcard's managed directory.
        await File(p.join(artifactDir.path, 'save.dat')).writeAsBytes(List.filled(64, 1));

        final fakeExe = p.join(exeDir, 'pcsx2-qt.exe');
        await File(fakeExe).writeAsString('');

        final ds = await _StubDirectoryService.create(exePath: fakeExe);
        final strategy = Pcsx2SaveStrategy(
          ds,
          await _testPrefs(),
          platform: const PlatformInfo('windows', environment: {}),
        );

        final zipBytes = await buildZip({
          'BASLUS-20502/save.dat': List.filled(64, 2),
        });

        final ok = await strategy.restoreSave(
          Game(id: 'g17', name: 'No Bak Game', platformSlug: 'ps2', fileSize: 0),
          exeDir,
          zipBytes,
          'No Bak Game.zip',
        );

        expect(ok, isTrue);
        final restoredFile = File(p.join(artifactDir.path, 'save.dat'));
        expect(await restoredFile.readAsBytes(), List.filled(64, 2),
            reason: 'the file itself must still be overwritten');

        final entries = artifactDir.listSync().map((e) => p.basename(e.path)).toList();
        expect(entries, ['save.dat'],
            reason: 'no .bak/.bak1/.bak2 files should be left inside the '
                'PCSX2-managed folder — got: $entries');
      } finally {
        await base.delete(recursive: true);
      }
    });
  });
}
