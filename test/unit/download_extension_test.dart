import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Mirrors the extension-preservation logic from DownloadService.download()
/// for single-file-foldered games (Issue #44).
///
/// [files] models `game.files` (the per-file metadata array) — often EMPTY
/// on the paginated list response the simple "Download" button acts on,
/// since it's only populated when full game details were separately
/// fetched. [fsExtension] models `game.fsExtension`, which RomM can send as
/// null (not just empty string) for single-file-foldered games.
/// [fsName]/[fileName] model the game's own top-level filename fields,
/// which are always present regardless of whether `files` was populated.
String resolveDownloadPath({
  required String romFilePath,
  required List<Map<String, dynamic>> files,
  String? fsExtension,
  String? fsName,
  String? fileName,
}) {
  final noFsExtension = fsExtension == null || fsExtension.isEmpty;
  final singleFileMeta = files.length == 1 ? files[0]['file_name']?.toString() : null;
  final fallbackFileName = singleFileMeta ?? fsName ?? fileName;
  final isSingleFileFoldered = noFsExtension && fallbackFileName != null && fallbackFileName.isNotEmpty;

  String finalPath = romFilePath;
  if (isSingleFileFoldered) {
    finalPath = '$finalPath/$fallbackFileName';
  }

  final currentExt = p.extension(finalPath).toLowerCase();
  if (currentExt.isEmpty && isSingleFileFoldered) {
    final metaExt = p.extension(fallbackFileName).toLowerCase();
    if (metaExt.isNotEmpty) {
      finalPath = '$finalPath$metaExt';
    }
  }

  return finalPath;
}

void main() {
  group('Issue #44 — Download extension preservation', () {
    test('single-file-foldered game preserves .chd extension (files populated)', () {
      // RomM stores: /roms/ps2/Gamename/Gamename.chd
      // fsName = "Gamename", fsExtension = "", files = [{"file_name": "Gamename.chd"}]
      final result = resolveDownloadPath(
        romFilePath: '/roms/ps2/Gamename',
        files: [
          {'file_name': 'Gamename.chd'}
        ],
        fsExtension: '',
      );
      expect(result, '/roms/ps2/Gamename/Gamename.chd');
    });

    test('single-file-foldered game preserves .iso extension (files populated)', () {
      final result = resolveDownloadPath(
        romFilePath: '/roms/psx/Game Name',
        files: [
          {'file_name': 'Game Name.iso'}
        ],
        fsExtension: '',
      );
      expect(result, '/roms/psx/Game Name/Game Name.iso');
    });

    // This is the actual real-world bug: the simple "Download" button calls
    // DownloadService.download() with a Game straight from the paginated
    // library list, where `files` is empty — only full game details (fetched
    // separately, e.g. via getGame()) populate it. The old logic required
    // `files.length == 1` to trigger folder-aware extension resolution, so
    // it silently never fired for this — by far the most common — call path.
    test('single-file-foldered game with EMPTY files array still resolves via fsName (issue #44 real case)', () {
      final result = resolveDownloadPath(
        romFilePath: '/roms/ps2/Gamename',
        files: [],
        fsExtension: '',
        fsName: 'Gamename.chd',
      );
      expect(result, '/roms/ps2/Gamename/Gamename.chd');
    });

    test('single-file-foldered game with EMPTY files array falls back to fileName when fsName is null', () {
      final result = resolveDownloadPath(
        romFilePath: '/roms/psx/Game Name',
        files: [],
        fsExtension: '',
        fileName: 'Game Name.iso',
      );
      expect(result, '/roms/psx/Game Name/Game Name.iso');
    });

    test('fsExtension: null (not empty string) is also treated as single-file-foldered', () {
      // RomM may send null rather than "" — a strict `== ''` check misses this.
      final result = resolveDownloadPath(
        romFilePath: '/roms/ngc/Game',
        files: [],
        fsExtension: null,
        fsName: 'Game.rvz',
      );
      expect(result, '/roms/ngc/Game/Game.rvz');
    });

    test('non-foldered game with fsExtension uses base path', () {
      // Normal case: fsName = "Game.chd", fsExtension = ".chd"
      final result = resolveDownloadPath(
        romFilePath: '/roms/ps2/Game.chd',
        files: [],
        fsExtension: '.chd',
        fsName: 'Game.chd',
      );
      expect(result, '/roms/ps2/Game.chd');
    });

    test('multi-file game uses base path (extraction handles it)', () {
      final result = resolveDownloadPath(
        romFilePath: '/roms/ps2/MultiDisc',
        files: [
          {'file_name': 'disc1.chd'},
          {'file_name': 'disc2.chd'},
          {'file_name': 'game.m3u'},
        ],
        fsExtension: '',
      );
      // Multi-file: singleFileMeta is null (files.length != 1), and with no
      // fsName/fileName fallback provided here, isSingleFileFoldered is false.
      expect(result, '/roms/ps2/MultiDisc');
    });

    test('no filename metadata available at all does not crash', () {
      final result = resolveDownloadPath(
        romFilePath: '/roms/ps2/Game',
        files: [],
        fsExtension: '',
      );
      expect(result, '/roms/ps2/Game');
    });

    test('file_name with no extension does not add spurious extension', () {
      final result = resolveDownloadPath(
        romFilePath: '/roms/ps2/Game',
        files: [
          {'file_name': 'GameData'}
        ],
        fsExtension: '',
      );
      // Both path and file_name have no extension — no extension added
      expect(result, '/roms/ps2/Game/GameData');
    });

    test('nested folder structure with .pbp extension', () {
      final result = resolveDownloadPath(
        romFilePath: '/roms/psx/Final Fantasy VII',
        files: [
          {'file_name': 'FF7.pbp'}
        ],
        fsExtension: '',
      );
      expect(result, '/roms/psx/Final Fantasy VII/FF7.pbp');
    });
  });
}
