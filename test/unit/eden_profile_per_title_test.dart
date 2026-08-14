import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/eden_save_strategy.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;

import 'save_sync_regression_test.mocks.dart';

/// Regression coverage for issue #68: with multiple Eden user profiles,
/// getSaveDir() picked the "most recently modified profile overall"
/// regardless of whether that profile actually had a save for the game
/// being synced. A user whose most-active profile belonged to a different
/// game than the one they were currently syncing would get "no save files
/// found" even though a real save existed under a less-recently-touched
/// profile.
void main() {
  late Directory tempDir;
  late MockDirectoryService mockDirService;

  setUp(() async {
    mockDirService = MockDirectoryService();
    when(mockDirService.findEmulatorExecutable(any, any)).thenAnswer((_) async => null);
    tempDir = await Directory.systemTemp.createTemp('eden_profile_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('getSaveDir prefers a profile that actually has this title\'s save over the globally-newest profile', () async {
    final appDataDir = p.join(tempDir.path, 'AppData');
    final saveBase = p.join(appDataDir, 'eden', 'nand', 'user', 'save', '0000000000000000');
    const newestProfile = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'; // most recently touched, but for a DIFFERENT game
    const correctProfile = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'; // older overall, but HAS this game's save
    // EdenSaveStrategy normalizes 16-char title IDs by zeroing the last 3
    // hex digits (the content-ID suffix distinguishing base/DLC/update), so
    // use IDs already in normalized ("...000") form and differing before
    // that suffix — not just in the part that gets zeroed out.
    const otherTitleId = '0100000000000000';
    const thisTitleId = '0100000000010000';

    // "Newest" profile: has a save, but for a different game.
    final newestOtherGame = Directory(p.join(saveBase, newestProfile, otherTitleId));
    await newestOtherGame.create(recursive: true);
    await File(p.join(newestOtherGame.path, 'save.bin')).writeAsString('data');

    // Older profile: has the actual save for the game we're syncing.
    final olderThisGame = Directory(p.join(saveBase, correctProfile, thisTitleId));
    await olderThisGame.create(recursive: true);
    await File(p.join(olderThisGame.path, 'save.bin')).writeAsString('data');
    // Make it clearly older than the "newest" profile's file.
    await File(p.join(olderThisGame.path, 'save.bin'))
        .setLastModified(DateTime.now().subtract(const Duration(days: 2)));

    final platform = PlatformInfo('windows', environment: {'APPDATA': appDataDir});
    final strategy = EdenSaveStrategy(mockDirService, platform: platform);
    // A romPath whose filename encodes the target title ID directly, so
    // _extractTitleIdFromFilename resolves it without needing real ROM bytes.
    final romPath = p.join(tempDir.path, 'roms', 'Game [$thisTitleId].nsp');
    final game = Game(id: 'g1', name: 'Game', platformSlug: 'switch', fileSize: 0);

    final saveDir = await strategy.getSaveDir(game, romPath);

    expect(saveDir, isNotNull);
    expect(saveDir, contains(correctProfile),
        reason: 'Should resolve to the profile that actually has a save for titleId=$thisTitleId, '
            'not just the profile with the globally-newest file');
    expect(saveDir, isNot(contains(newestProfile)));
  });
}
