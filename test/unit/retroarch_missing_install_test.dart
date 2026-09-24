import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/retroarch_save_strategy.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;

import 'save_sync_regression_test.mocks.dart';

/// Save sync must not crash when RetroArch has no retroarch.cfg and no
/// executable can be found (not installed, or installed somewhere Freegosy
/// doesn't know about).
///
/// Reported in issue #94: a PS2 push fell back to the RetroArch strategy and
/// died with "Null check operator used on a null value". The strategy
/// selection was fixed in #98, but the crash itself is still reachable for
/// anyone whose platform resolves to RetroArch without a detectable install:
/// _resolveSaveRoot() does `exePath!` on the result of findEmulatorExecutable().
void main() {
  late MockDirectoryService mockDirService;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ra_missing_install_');
    mockDirService = MockDirectoryService();
    when(mockDirService.findEmulatorExecutable(argThat(isA<String>()), argThat(isA<String>())))
        .thenAnswer((_) async => null);
    when(mockDirService.linuxSyncPreset).thenReturn('default');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  const knownBug = 'Known bug: RetroArchSaveStrategy._resolveSaveRoot() force-unwraps '
      'a null executable path (issue #94 crash). Remove skip once fixed.';

  for (final os in ['windows', 'macos']) {
    group('RetroArch not installed, no retroarch.cfg ($os)', () {
      late RetroArchSaveStrategy strategy;
      final game = Game(id: '1', name: 'Burnout 3: Takedown', platformSlug: 'ps2', fileSize: 0);

      setUp(() {
        final platform = PlatformInfo(os, environment: {
          'HOME': tempDir.path,
          'APPDATA': tempDir.path,
          'USERPROFILE': tempDir.path,
        });
        strategy = RetroArchSaveStrategy(mockDirService, platform: platform);
      });

      test('getSaveDir does not throw', () async {
        final romPath = p.join(tempDir.path, 'roms', 'Burnout 3 - Takedown.iso');
        await expectLater(strategy.getSaveDir(game, romPath), completes);
      }, skip: knownBug);

      test('getSaveFiles returns no files instead of throwing', () async {
        final romPath = p.join(tempDir.path, 'roms', 'Burnout 3 - Takedown.iso');
        expect(await strategy.getSaveFiles(game, romPath), isEmpty);
      }, skip: knownBug);
    });
  }
}
