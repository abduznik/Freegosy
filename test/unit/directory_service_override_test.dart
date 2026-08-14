import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DirectoryService path override', () {
    late DirectoryService directoryService;
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('dir_service_test');
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      directoryService = DirectoryService(prefs);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('setEmulatorPathOverride stores and retrieves override', () async {
      final overridePath = p.join(tempDir.path, 'custom_dolphin.exe');
      await File(overridePath).writeAsString('fake executable');

      await directoryService.setEmulatorPathOverride('dolphin', overridePath);
      final retrieved = directoryService.getEmulatorPathOverride('dolphin');

      expect(retrieved, overridePath);
    });

    test('findEmulatorExecutable uses path override when file exists', () async {
      final overridePath = p.join(tempDir.path, 'my_custom_emu.exe');
      await File(overridePath).writeAsString('fake executable');

      await directoryService.setEmulatorPathOverride('test_emu', overridePath);
      final found = await directoryService.findEmulatorExecutable('test_emu', 'my_custom_emu.exe');

      expect(found, overridePath);
    });

    test('findEmulatorExecutable searches override directory for executable', () async {
      final overrideDir = p.join(tempDir.path, 'custom_emus');
      await Directory(overrideDir).create(recursive: true);
      final exePath = p.join(overrideDir, 'dolphin-emu');
      await File(exePath).writeAsString('fake executable');

      await directoryService.setEmulatorPathOverride('dolphin', overrideDir);
      final found = await directoryService.findEmulatorExecutable('dolphin', 'dolphin-emu');

      expect(found, exePath);
    });

    test('findEmulatorExecutable falls back when override file missing', () async {
      final overridePath = p.join(tempDir.path, 'nonexistent.exe');

      await directoryService.setEmulatorPathOverride('test_emu2', overridePath);
      final found = await directoryService.findEmulatorExecutable('test_emu2', 'some_exe.exe');

      // Should return null since the override file doesn't exist
      // and the emulator directory doesn't exist either
      expect(found, isNull);
    });

    test('loadEmulatorPathOverride reads from SharedPreferences', () async {
      final rawPrefs = await SharedPreferences.getInstance();
      final overridePath = p.join(tempDir.path, 'loaded_emu.exe');
      await File(overridePath).writeAsString('fake');
      await rawPrefs.setString('emu_path_my_emu', overridePath);

      // Create new service and explicitly load overrides
      final newService = DirectoryService(SharedPreferencesAppPreferences(rawPrefs));
      newService.loadEmulatorPathOverrides();
      final retrieved = newService.getEmulatorPathOverride('my_emu');

      expect(retrieved, overridePath);
    });
  });
}
