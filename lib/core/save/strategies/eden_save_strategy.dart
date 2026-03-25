import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../../romm/romm_models.dart';
import '../save_strategy.dart';

/// Save strategy for Eden (Switch) emulator.
///
/// Save data is located in:
///   AppData/Roaming/eden/nand/user/save/0000000000000000/{profile}/{titleId}/
class EdenSaveStrategy extends SaveStrategy {
  @override
  String get strategyId => 'switch';

  static final RegExp _titleIdRegex = RegExp(r'01[0-9A-Fa-f]{14}');

  /// Attempt to extract a Switch title ID from [romPath] using three methods:
  /// 1. Regex match in the filename
  /// 2. Parse XCI header at offset 0x108 (8 bytes, reversed, hex)
  /// 3. Scan eden save folders for the most recently modified folder
  Future<String?> _resolveTitleId(String romPath, {DateTime? sessionStart}) async {
    // Method 1: regex in filename
    final fileName = romPath.replaceAll('\\', '/').split('/').last;
    final match = _titleIdRegex.firstMatch(fileName.toUpperCase());
    if (match != null) return match.group(0)!.toUpperCase();

    // Method 2: XCI header
    final titleFromHeader = await _parseTitleIdFromXci(romPath);
    if (titleFromHeader != null) return titleFromHeader;

    // Method 3: scan eden save folders
    return await _scanEdenSaveFolders(sessionStart);
  }

  Future<String?> _parseTitleIdFromXci(String romPath) async {
    if (!romPath.toLowerCase().endsWith('.xci')) return null;
    try {
      final file = File(romPath);
      if (!await file.exists()) return null;
      final raf = await file.open();
      try {
        await raf.setPosition(0x108);
        final bytes = await raf.read(8);
        if (bytes.length < 8) return null;
        // Reverse bytes and convert to hex
        final reversed = bytes.reversed.toList();
        final hex = reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
        if (_titleIdRegex.hasMatch(hex)) return hex;
        return null;
      } finally {
        await raf.close();
      }
    } catch (e) {
      return null;
    }
  }

  Future<String?> _scanEdenSaveFolders(DateTime? sessionStart) async {
    final edenSaveRoot = await _getEdenSaveRoot();
    if (edenSaveRoot == null) return null;

    final rootDir = Directory(edenSaveRoot);
    if (!await rootDir.exists()) return null;

    String? bestTitleId;
    DateTime? bestTime;

    try {
      // Scan all profile directories
      await for (final profileEntry in rootDir.list()) {
        if (profileEntry is! Directory) continue;
        await for (final titleEntry in profileEntry.list()) {
          if (titleEntry is! Directory) continue;
          final candidate = titleEntry.uri.pathSegments
              .lastWhere((s) => s.isNotEmpty, orElse: () => '');
          if (!_titleIdRegex.hasMatch(candidate.toUpperCase())) continue;
          final stat = await titleEntry.stat();
          if (sessionStart != null && stat.modified.isBefore(sessionStart)) continue;
          if (bestTime == null || stat.modified.isAfter(bestTime)) {
            bestTime = stat.modified;
            bestTitleId = candidate.toUpperCase();
          }
        }
      }
    } catch (e) {
      // Error handled silently
    }

    return bestTitleId;
  }

  Future<String?> _getEdenSaveRoot() async {
    try {
      final result = await Process.run(
        'cmd', ['/c', 'echo %APPDATA%'],
        runInShell: false,
      );
      final appData = result.stdout.toString().trim();
      if (appData.isEmpty || appData.contains('%APPDATA%')) return null;
      return '$appData/eden/nand/user/save/0000000000000000';
    } catch (e) {
      return null;
    }
  }

  Future<String?> _getSaveDirForTitleId(String titleId) async {
    final saveRoot = await _getEdenSaveRoot();
    if (saveRoot == null) return null;

    final rootDir = Directory(saveRoot);
    if (!await rootDir.exists()) await rootDir.create(recursive: true);

    try {
      await for (final entry in rootDir.list()) {
        if (entry is! Directory) continue;
        final titleDir = Directory('${entry.path}/$titleId');
        if (await titleDir.exists()) return titleDir.path;
      }

      final profiles = await rootDir.list().where((e) => e is Directory).toList();
      if (profiles.isNotEmpty) {
        final path = '${profiles.first.path}/$titleId';
        await Directory(path).create(recursive: true);
        return path;
      }

      throw Exception('Launch the game in Eden at least once before syncing saves');
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final titleId = await _resolveTitleId(romPath);
    if (titleId == null) return null;

    final saveRoot = await _getEdenSaveRoot();
    if (saveRoot == null) return null;

    // Find the first profile directory that contains this title
    final rootDir = Directory(saveRoot);
    if (!await rootDir.exists()) return null;

    try {
      await for (final entry in rootDir.list()) {
        if (entry is! Directory) continue;
        final titleDir = Directory('${entry.path}/$titleId');
        if (await titleDir.exists()) return titleDir.path;
      }
      // Default profile path (no profile folders yet)
      final profileDirs = await rootDir.list().toList();
      if (profileDirs.isNotEmpty && profileDirs.first is Directory) {
        return '${profileDirs.first.path}/$titleId';
      }
    } catch (e) {
      // Error handled silently
    }
    return null;
  }

  @override
Future<List<File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];
    final dir = Directory(saveDir);
    if (!await dir.exists()) return [];
    // Return a dummy File pointing to the directory
    // SaveSyncService will detect it's a directory and zip it
    return [File(saveDir)];
  }



    @override
    Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
      try {
        final titleMatch = _titleIdRegex.firstMatch(filename.toUpperCase());
        final saveDir = titleMatch != null
            ? await _getSaveDirForTitleId(titleMatch.group(0)!)
            : await getSaveDir(game, destPath);
        if (saveDir == null) return false;

        final dir = Directory(saveDir);
        if (!await dir.exists()) await dir.create(recursive: true);

        // RomM packages saves as zips — extract into the title directory.
        if (filename.toLowerCase().endsWith('.zip')) {
          return await _extractZipSave(data, saveDir);
        }

        final targetPath = '$saveDir/$filename';
        await backupSave(targetPath);
        await File(targetPath).writeAsBytes(data);
        return true;
      } catch (e) {
        rethrow;
      }
    }

  Future<bool> _extractZipSave(Uint8List data, String destDir) async {
    try {
      final archive = ZipDecoder().decodeBytes(data);
      for (final entry in archive) {
        // Strip the leading titleId folder from zip entry names
      final entryName = entry.name.contains('/')
          ? entry.name.substring(entry.name.indexOf('/') + 1)
          : entry.name;
      if (entryName.isEmpty) continue;
      final outPath = '$destDir/$entryName';
        if (entry.isFile) {
          await backupSave(outPath);
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}
