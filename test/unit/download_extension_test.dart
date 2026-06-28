import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Simulates the extension-preservation logic from DownloadService
/// for single-file-foldered games (Issue #44).
String resolveDownloadPath({
  required String romFilePath,
  required List<Map<String, dynamic>> files,
  required String fsExtension,
}) {
  bool isSingleFileFoldered = files.length == 1 && fsExtension == '';

  String finalPath = romFilePath;
  if (isSingleFileFoldered) {
    final fileName = files[0]["file_name"]?.toString();
    if (fileName != null && fileName.isNotEmpty) {
      finalPath = '$finalPath/$fileName';
    }
  }

  // Ensure the final path has a file extension.
  final currentExt = p.extension(finalPath).toLowerCase();
  if (currentExt.isEmpty && isSingleFileFoldered && files.isNotEmpty) {
    final metaFileName = files[0]["file_name"]?.toString() ?? '';
    final metaExt = p.extension(metaFileName).toLowerCase();
    if (metaExt.isNotEmpty) {
      finalPath = '$finalPath$metaExt';
    }
  }

  return finalPath;
}

void main() {
  group('Issue #44 — Download extension preservation', () {
    test('single-file-foldered game preserves .chd extension', () {
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

    test('single-file-foldered game preserves .iso extension', () {
      final result = resolveDownloadPath(
        romFilePath: '/roms/psx/Game Name',
        files: [
          {'file_name': 'Game Name.iso'}
        ],
        fsExtension: '',
      );
      expect(result, '/roms/psx/Game Name/Game Name.iso');
    });

    test('non-foldered game with fsExtension uses base path', () {
      // Normal case: fsName = "Game.chd", fsExtension = ".chd"
      final result = resolveDownloadPath(
        romFilePath: '/roms/ps2/Game.chd',
        files: [],
        fsExtension: '.chd',
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
      // Multi-file: isSingleFileFoldered is false, so path stays as-is
      expect(result, '/roms/ps2/MultiDisc');
    });

    test('empty files list does not crash', () {
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
