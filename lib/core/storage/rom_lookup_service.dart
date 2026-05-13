import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../romm/romm_models.dart';
import '../romm/rom_constants.dart';
import 'file_system_index.dart';

class RomLookupService {
  /// Tries to find the actual ROM file on disk.
  /// First checks the exact path, then tries common extensions for the platform.
  /// Returns the found path or null if not found.
  static Future<String?> findExistingRomPath(
    Game game, 
    String romDir, {
    FileSystemIndex? index,
  }) async {
    final platformLower = game.platformSlug?.toLowerCase();
    
    debugPrint('[Matching] Searching for ${game.name} (Platform: $platformLower) in $romDir');

    // Names to check (in order of priority)
    final namesToCheck = <String>[];
    if (game.fsName != null) namesToCheck.add(game.fsName!);
    if (game.fileName != null) namesToCheck.add(game.fileName!);
    
    final sanitizedName = game.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    namesToCheck.add(sanitizedName);

    // 1. Check using Index if provided (Case-Insensitive & Fast)
    if (index != null && (index.rootPath == romDir || index.rootPath == p.join(romDir, 'roms'))) {
      for (final name in namesToCheck) {
        final lowerName = name.toLowerCase();
        
        // Try exact name match (files)
        if (index.files.containsKey(lowerName)) {
          debugPrint('[Matching] Index hit (file): $lowerName');
          return index.files[lowerName];
        }
        
        // Try name match (dirs)
        if (index.dirs.containsKey(lowerName)) {
          debugPrint('[Matching] Index hit (dir): $lowerName');
          final found = await findMainRomInFolder(game, index.dirs[lowerName]!);
          if (found != null) return found;
        }

        // Try with extensions
        final extensions = RomConstants.platformExtensions[game.platformSlug?.toLowerCase()] ?? [];
        for (final ext in extensions) {
          final nameWithExt = lowerName.endsWith(ext.toLowerCase()) ? lowerName : '$lowerName${ext.toLowerCase()}';
          if (index.files.containsKey(nameWithExt)) return index.files[nameWithExt];
        }
      }
      
      // Fuzzy match in index (Last resort, only if name is very similar and not ambiguous)
      for (final name in namesToCheck) {
        final lowerName = name.toLowerCase();
        for (final entry in index.files.entries) {
          if (entry.key.startsWith(lowerName) && entry.key.length < lowerName.length + 5 && !entry.key.endsWith('.part')) {
            return entry.value;
          }
        }
      }
    }

    // 2. Fallback to manual scanning (Legacy/Direct)
    final baseName = game.fsName ?? game.fileName ?? sanitizedName;
    
    // Check exact path first
    final exactPath = p.join(romDir, baseName);
    if (await io.File(exactPath).exists()) return p.absolute(exactPath);
    
    // Case-insensitive check by scanning parent directory manually
    final parentDir = io.Directory(romDir);
    if (await parentDir.exists()) {
      try {
        await for (final entity in parentDir.list()) {
          final fname = p.basename(entity.path);
          if (fname.toLowerCase() == baseName.toLowerCase()) {
            if (entity is io.File) return p.absolute(entity.path);
            if (entity is io.Directory) {
              final found = await findMainRomInFolder(game, entity.path);
              if (found != null) return found;
            }
          }
        }
      } catch (_) {}
    }

    // 3. Search for multi-file folder
    final folderName = sanitizedName;
    final searchDirs = [romDir, p.join(romDir, 'roms')];
    
    for (final dirPath in searchDirs) {
      final pDir = io.Directory(dirPath);
      if (!await pDir.exists()) continue;

      try {
        await for (final entity in pDir.list()) {
          if (entity is io.Directory) {
            final dName = p.basename(entity.path);
            if (dName.toLowerCase() == folderName.toLowerCase()) {
              final found = await findMainRomInFolder(game, entity.path);
              if (found != null) return found;
            }
          }
        }
      } catch (_) {}
    }

    // 4. Try common extensions for this platform
    final extensions = RomConstants.platformExtensions[platformLower] ?? [];
    for (final dirPath in searchDirs) {
      final pDir = io.Directory(dirPath);
      if (!await pDir.exists()) continue;
      
      try {
        final List<io.FileSystemEntity> entities = await pDir.list().toList();
        for (final ext in extensions) {
          for (final entity in entities) {
            if (entity is io.File) {
              final fname = p.basename(entity.path).toLowerCase();
              final target = '$baseName$ext'.toLowerCase();
              if (fname == target || fname == baseName.toLowerCase()) {
                return p.absolute(entity.path);
              }
            }
          }
        }
      } catch (_) {}
    }

    // 5. Scan directory for fuzzy file match
    for (final dirPath in searchDirs) {
      final pDir = io.Directory(dirPath);
      if (!await pDir.exists()) continue;

      try {
        await for (final entity in pDir.list()) {
          if (entity is io.File) {
            final fname = p.basename(entity.path).toLowerCase();
            final target = baseName.toLowerCase();
            if (fname == target || fname == '$target.iso' || fname == '$target.bin' || fname == '$target.pkg') {
              return p.absolute(entity.path);
            }
          }
        }
      } catch (_) {}
    }

    debugPrint('[Matching] No match found for ${game.name}');
    return null;
  }

  /// Finds the largest ROM-like file in a folder.
  static Future<String?> findMainRomInFolder(Game game, String folderPath) async {
    final platform = game.platformSlug?.toLowerCase() ?? '';
    final isFolderBased = ['windows', 'pc', 'win', 'ps3', 'switch', 'nintendo-switch'].contains(platform);
    
    final extensions = RomConstants.platformExtensions[game.platformSlug?.toLowerCase()] ?? [];
    
    io.File? largestFile;
    int largestSize = 0;

    try {
      await for (final entity in io.Directory(folderPath).list(recursive: true)) {
        if (entity is io.File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (extensions.isEmpty || extensions.contains(ext)) {
            final size = await entity.length();
            if (size > largestSize) {
              largestSize = size;
              largestFile = entity;
            }
          }
        }
      }
    } catch (_) {}

    if (largestFile != null) {
      return p.absolute(largestFile.path);
    }
    
    if (isFolderBased) return p.absolute(folderPath);
    
    return null;
  }

  /// Fuzzy resolver specifically for platform strategies (like Eden).
  static Future<String?> resolveFuzzyRomFile(String romPath, List<String> allowedExtensions) async {
    if (io.File(romPath).existsSync()) return romPath;

    for (final ext in allowedExtensions) {
      final withExt = '$romPath$ext';
      if (io.File(withExt).existsSync()) return withExt;
    }

    if (io.Directory(romPath).existsSync()) {
      return _findLargestFileByExt(romPath, allowedExtensions);
    }

    final parentPath = p.dirname(romPath);
    final parentDir = io.Directory(parentPath);
    if (!parentDir.existsSync()) return null;

    final baseName = p.basenameWithoutExtension(romPath);
    final searchTokens = _tokenize(baseName);
    if (searchTokens.isEmpty) return null;

    io.File? bestMatch;
    int bestScore = 0;

    for (final entity in parentDir.listSync()) {
      if (entity is! io.File) continue;
      final fileName = p.basename(entity.path).toLowerCase();
      if (!allowedExtensions.any((ext) => fileName.endsWith(ext))) continue;

      final fileTokens = _tokenize(p.basenameWithoutExtension(entity.path));
      int score = 0;
      for (final token in searchTokens) {
        if (fileTokens.contains(token)) score++;
      }

      if (score > bestScore && score >= (searchTokens.length / 2).ceil()) {
        bestScore = score;
        bestMatch = entity;
      }
    }

    return bestMatch?.path;
  }

  static String? _findLargestFileByExt(String dirPath, List<String> extensions) {
    io.File? largest;
    int maxSize = -1;
    try {
      for (final entity in io.Directory(dirPath).listSync(recursive: true)) {
        if (entity is! io.File) continue;
        final name = entity.path.toLowerCase();
        if (!extensions.any((ext) => name.endsWith(ext))) continue;
        final size = entity.lengthSync();
        if (size > maxSize) {
          maxSize = size;
          largest = entity;
        }
      }
    } catch (_) {}
    return largest?.path;
  }

  static Set<String> _tokenize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\[[^\]]*\]'), '') 
        .replaceAll(RegExp(r'\([^)]*\)'), '') 
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ') 
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1) 
        .toSet();
  }
}
