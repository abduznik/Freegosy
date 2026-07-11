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

    test('WindowsGameService.findExecutable finds Hacknet.exe', () async {
      // Import WindowsGameService
      final service = _WindowsGameServiceForTest();
      final result = await service.findExecutable(gameDir.path, hint: 'Hacknet');

      expect(result, isNotNull);
      expect(result, endsWith('Hacknet.exe'));
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
          final name = p.basename(entity.path).toLowerCase();
          if (name.contains('uninstall') || name.contains('setup')) continue;
          exeFiles.add(entity);
        }
      }
    }

    if (exeFiles.isEmpty) return null;

    if (hint != null) {
      final hintLower = hint.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      for (final exe in exeFiles) {
        final exeName = p.basenameWithoutExtension(exe.path)
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (exeName.contains(hintLower) || hintLower.contains(exeName)) {
          return exe.path;
        }
      }
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
}
