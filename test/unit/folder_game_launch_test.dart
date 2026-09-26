import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/emulator/game_launch_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/rom_constants.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/backup_repository.dart';
import 'package:freegosy/core/save/backup_service.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/rom_lookup_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firmware_service_test.mocks.dart';

/// Folder games (ScummVM) launch from their whole folder: nothing inside
/// the folder may be picked as "the ROM".
void main() {
  late Directory tmp;
  late Directory gameDir;
  late GameLaunchService launchService;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('folder_game');
    gameDir = Directory(p.join(tmp.path, 'Beneath a Steel Sky'));
    await gameDir.create();
    await File(p.join(gameDir.path, 'sky.dnr')).writeAsString('x' * 10);
    await File(p.join(gameDir.path, 'sky.dsk')).writeAsString('x' * 1000);
    await File(p.join(gameDir.path, 'extras.zip')).writeAsString('x' * 5000);

    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final dirService = DirectoryService(prefs);
    final registry = StrategyRegistry(dirService, prefs);
    launchService = GameLaunchService(
      directoryService: dirService,
      strategyRegistry: registry,
      saveSyncService: SaveSyncService(MockRommService(), dirService, registry, prefs),
      backupService: BackupService(),
      backupRepository: BackupRepository(),
      prefs: prefs,
    );
  });

  tearDown(() => tmp.delete(recursive: true));

  Game game(String slug) => Game(id: '1', name: 'Beneath a Steel Sky', platformSlug: slug, fileSize: 0);

  test('findMainRomInFolder returns the ScummVM game folder, not its largest file', () async {
    final result = await RomLookupService.findMainRomInFolder(game('scummvm'), gameDir.path);
    expect(result, p.absolute(gameDir.path));
  });

  test('platform slug matching is case-insensitive', () async {
    final result = await RomLookupService.findMainRomInFolder(game('ScummVM'), gameDir.path);
    expect(result, p.absolute(gameDir.path));
    expect(RomConstants.isFolderGamePlatform('SCUMMVM'), isTrue);
  });

  test('resolveRomFileInDirectory keeps the folder for ScummVM', () async {
    expect(await launchService.resolveRomFileInDirectory(gameDir.path, 'scummvm'), gameDir.path);
  });

  test('other platforms still resolve a file inside the folder', () async {
    final resolved = await launchService.resolveRomFileInDirectory(gameDir.path, 'arcade');
    expect(p.dirname(resolved), gameDir.path);
    expect(p.basename(resolved), 'extras.zip');
  });

  test('ScummVM has no extension list, so its archives are extracted after download', () {
    expect(RomConstants.platformExtensions.containsKey('scummvm'), isFalse);
  });
}
