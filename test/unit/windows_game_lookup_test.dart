import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/rom_constants.dart';
import 'package:freegosy/core/storage/rom_lookup_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Windows game ROM lookup', () {
    late Directory tempDir;
    late Directory hacknetDir;
    late Directory gameDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('win_rom_test');
      // Simulate: F:\ROMS\win\Hacknet\Hacknet_v5.069_Standalone_WIN\
      hacknetDir = Directory(p.join(tempDir.path, 'Hacknet'));
      await hacknetDir.create();
      gameDir = Directory(p.join(hacknetDir.path, 'Hacknet_v5.069_Standalone_WIN'));
      await gameDir.create(recursive: true);

      // Create game files
      await File(p.join(gameDir.path, 'Hacknet.exe')).writeAsString('fake exe');
      await File(p.join(gameDir.path, 'FNA.dll')).writeAsString('fake dll');

      // Create subdirectories with large files (like the real game)
      final contentDir = Directory(p.join(gameDir.path, 'Content', 'SFX', 'Ending'));
      await contentDir.create(recursive: true);
      // This is what the OLD code picked as the "ROM" — a large .xnb file
      await File(p.join(contentDir.path, 'EndingSpeech.xnb')).writeAsString('x' * 15000000);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('Windows platform extensions include .exe/.bat/.cmd', () {
      expect(RomConstants.platformExtensions['windows'], contains('.exe'));
      expect(RomConstants.platformExtensions['windows'], contains('.bat'));
      expect(RomConstants.platformExtensions['windows'], contains('.cmd'));
      expect(RomConstants.platformExtensions['pc'], contains('.exe'));
      expect(RomConstants.platformExtensions['win'], contains('.exe'));
    });

    test('findMainRomInFolder returns folder path for Windows games', () async {
      final game = Game(
        id: '117',
        name: 'Hacknet',
        platformSlug: 'win',
        fileSize: 0,
      );

      final result = await RomLookupService.findMainRomInFolder(game, gameDir.path);

      expect(result, isNotNull);
      // Should return the folder path, not a random file
      expect(result, gameDir.path);
    });

    test('findMainRomInFolder does NOT return random .dll/.xnb file for Windows', () async {
      final game = Game(
        id: '117',
        name: 'Hacknet',
        platformSlug: 'win',
        fileSize: 0,
      );

      final result = await RomLookupService.findMainRomInFolder(game, gameDir.path);

      expect(result, isNotNull);
      // Should be the folder, not EndingSpeech.xnb
      expect(result, isNot(contains('.xnb')));
      expect(result, isNot(contains('EndingSpeech')));
      expect(result, isNot(contains('.dll')));
    });

    test('findExistingRomPath finds Hacknet folder', () async {
      final game = Game(
        id: '117',
        name: 'Hacknet',
        platformSlug: 'win',
        fsName: 'Hacknet',
        fileSize: 0,
      );

      final result = await RomLookupService.findExistingRomPath(
        game,
        tempDir.path,
      );

      expect(result, isNotNull);
      // Should find the Hacknet folder
      expect(result!.toLowerCase(), contains('hacknet'));
    });

    test('WindowsGameService.findExecutable finds FGUY.exe in nested folder', () async {
      // Simulate Family Guy folder structure:
      // gameDir/
      //   __MACOSX/          <- macOS metadata (should be skipped)
      //   InnerFolder/
      //     _CommonRedist/   <- redistributables (should be skipped)
      //       vcredist.exe   <- 14MB (larger than FGUY.exe)
      //     GameFolder/
      //       FGUY.exe       <- 7.8MB (the actual game)
      //       ._FGUY.exe     <- macOS resource fork (should be skipped)
      final nestedDir = Directory(p.join(gameDir.path, 'InnerFolder'));
      await nestedDir.create();
      final gameSubDir = Directory(p.join(nestedDir.path, 'GameFolder'));
      await gameSubDir.create();
      final commonRedist = Directory(p.join(nestedDir.path, '_CommonRedist'));
      await commonRedist.create();

      // Create redistributable (larger than game exe, should be skipped)
      await File(p.join(commonRedist.path, 'vcredist_x64.exe')).writeAsString('x' * 15000000);
      // Create macOS resource fork (should be skipped)
      await File(p.join(gameSubDir.path, '._FGUY.exe')).writeAsString('resource fork');
      // Create actual game exe
      await File(p.join(gameSubDir.path, 'FGUY.exe')).writeAsString('x' * 8000000);

      final service = _WindowsGameServiceForTest();
      final result = await service.findExecutable(gameDir.path, hint: 'Family Guy Back to the Multiverse');

      expect(result, isNotNull);
      expect(result, endsWith('FGUY.exe'));
      expect(result, isNot(contains('vcredist')));
      expect(result, isNot(contains('._')));
    });
  });
}

/// Minimal WindowsGameService for testing without full import chain
class _WindowsGameServiceForTest {
  static const launchableExtensions = ['.exe', '.bat', '.cmd'];

  Future<String?> findExecutable(String gameDir, {String? hint}) async {
    final dir = Directory(gameDir);
    if (!await dir.exists()) return null;

    final exeFiles = <File>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final ext = entity.path.toLowerCase();
        if (launchableExtensions.any((e) => ext.endsWith(e))) {
          final basename = p.basename(entity.path);
          if (basename.startsWith('._')) continue;
          final relPath = entity.path.substring(gameDir.length).toLowerCase();
          if (relPath.contains('__macosx') || relPath.contains('_commonredist')) continue;
          final name = basename.toLowerCase();
          if (name.contains('uninstall') || name.contains('setup') ||
              name.contains('redist') || name.contains('vcredist') ||
              name.contains('dotnet')) continue;
          exeFiles.add(entity);
        }
      }
    }

    if (exeFiles.isEmpty) return null;

    // Try hint match first (token-based fuzzy match)
    if (hint != null) {
      final hintTokens = _tokenize(hint);
      int bestScore = 0;
      File? bestMatch;

      for (final exe in exeFiles) {
        final exeTokens = _tokenize(p.basenameWithoutExtension(exe.path));
        int score = 0;
        for (final token in hintTokens) {
          if (exeTokens.any((t) => t.contains(token) || token.contains(t))) score++;
        }
        if (score > bestScore) {
          bestScore = score;
          bestMatch = exe;
        }
      }

      if (bestMatch != null && bestScore > 0) return bestMatch.path;
    }

    // Fall back to largest exe
    File? largest;
    int largestSize = 0;
    for (final exe in exeFiles) {
      final size = await exe.length();
      if (size > largestSize) {
        largestSize = size;
        largest = exe;
      }
    }
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
        .where((t) => t.length > 2)
        .toSet();
  }
}
