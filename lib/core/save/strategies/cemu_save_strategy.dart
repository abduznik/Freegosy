import 'dart:io' as io;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for Cemu (Wii U).
class CemuSaveStrategy extends SaveStrategy {
  final DirectoryService _directoryService;

  CemuSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'cemu';

  Future<String> _getSaveRoot({String? platformSlug}) async {
    // 1. Check emulator-relative path first (e.g. for Windows portable)
    final emuDir = await _directoryService.getEmulatorDirectory('cemu');
    final portableRoot = p.join(emuDir, 'mlc01', 'usr', 'save');
    if (await io.Directory(portableRoot).exists()) {
      return portableRoot;
    }

    // 2. Dynamic path resolution for macOS/Windows/Linux
    final baseDir = await _directoryService.getEmulatorAppSupportDirectory('Cemu', platformSlug: platformSlug);
    // On macOS, Cemu's save structure might be different in Application Support,
    // but typically it mirrors the internal folder structure if using the same mlc01 logic.
    // Actually, Cemu on macOS often puts mlc01 directly in Application Support/Cemu
    final resolvedPath = p.join(baseDir, 'mlc01', 'usr', 'save');

    if (!await io.Directory(resolvedPath).exists()) {
      throw Exception('Save directory not found for Cemu at $resolvedPath. Please launch Cemu at least once to generate save data.');
    }
    return resolvedPath;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    return await _getSaveRoot(platformSlug: game.platformSlug);
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveRoot = await _getSaveRoot(platformSlug: game.platformSlug);
    final saveBase = io.Directory(p.join(saveRoot, '00050000'));
    if (!await saveBase.exists()) return [];
    return [io.File(saveBase.path)]; // Return the directory as a single item
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final saveRoot = await _getSaveRoot(platformSlug: game.platformSlug);
      
      // Follow symlink if needed
      String resolvedRoot = saveRoot;
      try {
        if (await io.FileSystemEntity.isLink(saveRoot)) {
          resolvedRoot = await io.Link(saveRoot).resolveSymbolicLinks();
        }
      } catch (_) {}

      await io.Directory(resolvedRoot).create(recursive: true);
      
      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final entry in archive) {
          if (entry.name.contains('.bak') || entry.name == 'freegosy_sync.txt') continue;
          
          String cleanName = entry.name.replaceAll('\\', '/');
          final parts = cleanName.split('/');
          
          // Strip redundant Wii U prefixes
          int skipCount = 0;
          for (int i = 0; i < parts.length; i++) {
            final pPart = parts[i].toLowerCase();
            if (pPart == 'mlc01' || pPart == 'usr' || pPart == 'save') {
              skipCount = i + 1;
            }
          }
          if (skipCount > 0) {
            cleanName = p.joinAll(parts.sublist(skipCount));
          }
          if (cleanName.isEmpty) continue;
          
          final targetPath = p.normalize(p.join(resolvedRoot, cleanName));
          if (entry.isFile) {
            await backupSave(targetPath);
            final outFile = io.File(targetPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          } else {
            await io.Directory(targetPath).create(recursive: true);
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Cemu] Restore error: $e');
      rethrow;
    }
  }
}
