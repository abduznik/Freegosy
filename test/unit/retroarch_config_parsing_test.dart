import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/retroarch_save_strategy.dart';
import 'package:freegosy/core/save/save_strategy.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;

import 'save_sync_regression_test.mocks.dart';

void main() {
  late MockDirectoryService mockDirService;

  setUp(() {
    mockDirService = MockDirectoryService();
    when(mockDirService.findEmulatorExecutable(
            argThat(isA<String>()), argThat(isA<String>())))
        .thenAnswer((_) async => null);
    when(mockDirService.linuxSyncPreset).thenReturn('default');
  });

  group('RetroArch config parsing: sort_savefiles_enable', () {
    test('sort_savefiles_enable=true appends core subfolder (Linux)', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_sort_true_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'sort_savefiles_enable = "true"',
        'video_fullscreen = "false"',
      ].join('\n'));

      await Directory(p.join(tempDir.path, 'saves', 'mGBA')).create(recursive: true);

      when(mockDirService.getEmulatorAppSupportDirectory('retroarch', platformSlug: anyNamed('platformSlug')))
          .thenAnswer((_) async => configDir);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final strategy = RetroArchSaveStrategy(mockDirService, platform: platform);

      final game = Game(id: '1', name: 'Pokemon', platformSlug: 'gba', fileSize: 0);
      final romPath = p.join(tempDir.path, 'roms', 'Pokemon.gba');
      final result = await strategy.getSaveDir(game, romPath);

      expect(result, isNotNull);
      expect(result, endsWith('mGBA'),
          reason: 'sort_savefiles_enable=true should append core subfolder');

      await tempDir.delete(recursive: true);
    });

    test('sort_savefiles_enable=false returns flat saves directory (Linux)', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_sort_false_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'sort_savefiles_enable = "false"',
        'video_fullscreen = "false"',
      ].join('\n'));

      await Directory(p.join(tempDir.path, 'saves')).create(recursive: true);

      when(mockDirService.getEmulatorAppSupportDirectory('retroarch', platformSlug: anyNamed('platformSlug')))
          .thenAnswer((_) async => configDir);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final strategy = RetroArchSaveStrategy(mockDirService, platform: platform);

      final game = Game(id: '1', name: 'Pokemon', platformSlug: 'gba', fileSize: 0);
      final romPath = p.join(tempDir.path, 'roms', 'Pokemon.gba');
      final result = await strategy.getSaveDir(game, romPath);
      final expected = p.join(configDir, 'saves');

      expect(result, isNotNull);
      expect(result, isNot(endsWith('mGBA')),
          reason: 'sort_savefiles_enable=false must NOT append core subfolder');
      expect(result, equals(expected),
          reason: 'Should return the base dir without core subfolder');

      await tempDir.delete(recursive: true);
    });

    test('sort_savefiles_enable not set defaults to true (RetroArch default)', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_sort_default_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'video_fullscreen = "false"',
      ].join('\n'));

      await Directory(p.join(tempDir.path, 'saves', 'mGBA')).create(recursive: true);

      when(mockDirService.getEmulatorAppSupportDirectory('retroarch', platformSlug: anyNamed('platformSlug')))
          .thenAnswer((_) async => configDir);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final strategy = RetroArchSaveStrategy(mockDirService, platform: platform);

      final game = Game(id: '1', name: 'Pokemon', platformSlug: 'gba', fileSize: 0);
      final romPath = p.join(tempDir.path, 'roms', 'Pokemon.gba');
      final result = await strategy.getSaveDir(game, romPath);

      expect(result, isNotNull);
      expect(result, endsWith('mGBA'),
          reason: 'Default should be true (append core subfolder)');

      await tempDir.delete(recursive: true);
    });

    test('sort_savefiles_enable with extra whitespace and no quotes', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_sort_ws_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'sort_savefiles_enable = false',
        'video_fullscreen = "false"',
      ].join('\n'));

      await Directory(p.join(tempDir.path, 'saves')).create(recursive: true);

      when(mockDirService.getEmulatorAppSupportDirectory('retroarch', platformSlug: anyNamed('platformSlug')))
          .thenAnswer((_) async => configDir);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final strategy = RetroArchSaveStrategy(mockDirService, platform: platform);

      final game = Game(id: '1', name: 'Pokemon', platformSlug: 'gba', fileSize: 0);
      final romPath = p.join(tempDir.path, 'roms', 'Pokemon.gba');
      final result = await strategy.getSaveDir(game, romPath);

      expect(result, isNotNull);
      expect(result, isNot(endsWith('mGBA')),
          reason: 'Unquoted false should also be parsed correctly');

      await tempDir.delete(recursive: true);
    });
  });

  group('RetroArch config parsing: savefiles_in_content_dir', () {
    test('savefiles_in_content_dir=true returns ROM parent directory (macOS)', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_content_dir_');
      final configDir = p.join(tempDir.path, 'Library', 'Application Support', 'RetroArch', 'config');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'savefiles_in_content_dir = "true"',
        'video_fullscreen = "false"',
      ].join('\n'));

      // Create the expected saves dir with core subfolder (needed for non-content-dir path)
      await Directory(p.join(tempDir.path, 'saves', 'mGBA')).create(recursive: true);

      final platform = PlatformInfo('macos', environment: {'HOME': tempDir.path});
      final strategy = RetroArchSaveStrategy(mockDirService, platform: platform);

      final romDir = p.join(tempDir.path, 'roms', 'gba');
      await Directory(romDir).create(recursive: true);
      final romPath = p.join(romDir, 'Pokemon.gba');

      final game = Game(id: '1', name: 'Pokemon', platformSlug: 'gba', fileSize: 0);
      final result = await strategy.getSaveDir(game, romPath);

      expect(result, isNotNull);
      expect(result, equals(romDir),
          reason: 'savefiles_in_content_dir=true should return ROM parent dir');

      await tempDir.delete(recursive: true);
    });
  });

  group('RetroArch config parsing: static retroarchCoreSaveDir', () {
    test('sort_savefiles_enable=false returns flat dir without core subfolder', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_static_sort_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'sort_savefiles_enable = "false"',
      ].join('\n'));

      await Directory(p.join(tempDir.path, 'saves')).create(recursive: true);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final result = await SaveStrategy.retroarchCoreSaveDir(
        mockDirService, 'mGBA', platform: platform);

      expect(result, isNotNull);
      expect(result, equals(p.join(tempDir.path, 'saves')),
          reason: 'sort=false should return flat dir, not core subfolder');

      await tempDir.delete(recursive: true);
    });

    test('sort_savefiles_enable=true returns core subfolder', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_static_sort_true_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'sort_savefiles_enable = "true"',
      ].join('\n'));

      await Directory(p.join(tempDir.path, 'saves', 'mGBA')).create(recursive: true);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final result = await SaveStrategy.retroarchCoreSaveDir(
        mockDirService, 'mGBA', platform: platform);

      expect(result, isNotNull);
      expect(result, endsWith('mGBA'),
          reason: 'sort=true should append core subfolder');

      await tempDir.delete(recursive: true);
    });

    test('sort_savefiles_enable not set defaults to true', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_static_default_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
      ].join('\n'));

      await Directory(p.join(tempDir.path, 'saves', 'mGBA')).create(recursive: true);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final result = await SaveStrategy.retroarchCoreSaveDir(
        mockDirService, 'mGBA', platform: platform);

      expect(result, isNotNull);
      expect(result, endsWith('mGBA'),
          reason: 'Default should be true (append core subfolder)');

      await tempDir.delete(recursive: true);
    });
  });

  group('RetroArch EmuDeck-for-Windows detection', () {
    test('resolves saves under emudeck RetroArch root when detected', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_emudeck_win_');
      final retroArchRoot = p.join(
          tempDir.path, 'emudeck', 'EmulationStation-DE', 'Emulators', 'RetroArch');
      await Directory(p.join(retroArchRoot, 'saves', 'mGBA')).create(recursive: true);

      final platform = PlatformInfo('windows', environment: {
        'USERPROFILE': tempDir.path,
        'APPDATA': p.join(tempDir.path, 'AppData', 'Roaming'),
      });
      final strategy = RetroArchSaveStrategy(mockDirService, platform: platform);

      final game = Game(id: '1', name: 'Pokemon', platformSlug: 'gba', fileSize: 0);
      final romPath = p.join(tempDir.path, 'roms', 'Pokemon.gba');
      final result = await strategy.getSaveDir(game, romPath);

      expect(result, isNotNull);
      expect(result, equals(p.join(retroArchRoot, 'saves', 'mGBA')),
          reason: 'Should resolve directly under the EmuDeck-for-Windows RetroArch root');

      await tempDir.delete(recursive: true);
    });

    test('falls back to normal Windows resolution when emudeck root absent', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_no_emudeck_win_');
      final exeDir = p.join(tempDir.path, 'RetroArch-Win64');
      await Directory(exeDir).create(recursive: true);
      final exePath = p.join(exeDir, 'RetroArch.exe');
      await File(exePath).writeAsString('');

      when(mockDirService.findEmulatorExecutable('retroarch', 'RetroArch.exe'))
          .thenAnswer((_) async => exePath);

      final platform = PlatformInfo('windows', environment: {
        'USERPROFILE': tempDir.path,
        'APPDATA': p.join(tempDir.path, 'AppData', 'Roaming'),
      });
      final strategy = RetroArchSaveStrategy(mockDirService, platform: platform);

      final game = Game(id: '1', name: 'Pokemon', platformSlug: 'gba', fileSize: 0);
      final romPath = p.join(tempDir.path, 'roms', 'Pokemon.gba');
      final result = await strategy.getSaveDir(game, romPath);

      expect(result, equals(p.join(exeDir, 'saves', 'mGBA')),
          reason: 'Without an emudeck folder present, should resolve relative to the exe as before');

      await tempDir.delete(recursive: true);
    });
  });
}
