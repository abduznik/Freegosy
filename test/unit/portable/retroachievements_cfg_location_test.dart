import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/strategies/retroarch_strategy.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/portable/portable_mode.dart';
import 'package:freegosy/core/portable/portable_paths.dart';
import 'package:freegosy/core/retroachievements/retroachievements_emulator_login.dart';
import 'package:freegosy/core/storage/secure_storage_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../save_sync_regression_test.mocks.dart';
import 'portable_credential_store_test_helpers.dart';

class _Installed extends PathProviderPlatform {
  _Installed(this.base);
  final String base;
  @override
  Future<String?> getApplicationSupportPath() async => p.join(base, 'AppData');
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(base, 'Documents');
}

/// The RetroAchievements token is per PC (spec), so a portable copy writes
/// RetroArch's token file to the PC's own folder, never to the stick.
void main() {
  late io.Directory tmp;
  late PathProviderPlatform pathBefore;
  late SharedPreferencesStorePlatform prefsBefore;
  late String root, installedSupport;

  setUp(() async {
    tmp = await io.Directory.systemTemp.createTemp('ra_cfg_portable');
    pathBefore = PathProviderPlatform.instance;
    prefsBefore = SharedPreferencesStorePlatform.instance;
    root = p.join(tmp.path, 'Freegosy');
    installedSupport = p.join(tmp.path, 'AppData');
    await PortableMode.install(root, previous: _Installed(tmp.path), credentials: (dir) => fakeCredentialStore(dir));
  });

  tearDown(() async {
    PathProviderPlatform.instance = pathBefore;
    SharedPreferencesStorePlatform.instance = prefsBefore;
    PortableMode.current = null;
    PortablePaths.active = null;
    SecureStorageService.useStore(null);
    await tmp.delete(recursive: true);
  });

  test('RetroArch gets its token file from the PC folder, not the portable data folder', () async {
    final strategy = RetroArchStrategy(MockDirectoryService(),
        platform: const PlatformInfo('windows'),
        raLoginLoader: () async => const RetroAchievementsEmulatorLogin(username: 'u', token: 'secret'));

    final args = await strategy.retroAchievementsLaunchArgs();

    expect(args.first, '--appendconfig');
    expect(args.last, p.join(installedSupport, kRetroArchAchievementsConfigFileName));
    expect(io.File(args.last).readAsStringSync(), contains('secret'));
    expect(io.File(p.join(root, 'userdata', 'support', kRetroArchAchievementsConfigFileName)).existsSync(), isFalse);
  });

  test('disconnecting deletes the token file from the PC folder', () async {
    final file = io.File(p.join(installedSupport, kRetroArchAchievementsConfigFileName));
    await file.create(recursive: true);

    await RetroAchievementsEmulatorLogin.deleteEmulatorFiles();

    expect(file.existsSync(), isFalse);
  });
}
