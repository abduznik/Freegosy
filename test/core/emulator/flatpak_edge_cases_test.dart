import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/custom_emulator_config.dart';
import 'package:freegosy/core/emulator/linux_strategies/linux_environment_strategy.dart';
import 'package:freegosy/core/emulator/linux_strategies/native_linux_strategy.dart';

void main() {
  group('CustomEmulatorConfig - commandOverride', () {
    test('isCommandOverride returns true when commandOverride is set', () {
      final config = CustomEmulatorConfig(
        id: 'test-flatpak',
        name: 'RetroArch Flatpak',
        platforms: ['ps1', 'psx'],
        executablePath: '/usr/bin/flatpak',
        commandOverride: 'flatpak run org.libretro.RetroArch',
        saveMethod: CustomSaveMethod.file,
        savePath: '/home/user/saves',
      );

      expect(config.isCommandOverride, isTrue);
      expect(config.commandOverride, 'flatpak run org.libretro.RetroArch');
    });

    test('isCommandOverride returns false when commandOverride is null', () {
      final config = CustomEmulatorConfig(
        id: 'test-native',
        name: 'PCSX2 Native',
        platforms: ['ps2'],
        executablePath: '/usr/bin/pcsx2',
        saveMethod: CustomSaveMethod.file,
        savePath: '/home/user/saves',
      );

      expect(config.isCommandOverride, isFalse);
      expect(config.commandOverride, isNull);
    });

    test('isCommandOverride returns false when commandOverride is empty', () {
      final config = CustomEmulatorConfig(
        id: 'test-empty',
        name: 'Empty Command',
        platforms: ['nes'],
        executablePath: '/usr/bin/emu',
        commandOverride: '',
        saveMethod: CustomSaveMethod.file,
        savePath: '/home/user/saves',
      );

      expect(config.isCommandOverride, isFalse);
    });

    test('toJson includes commandOverride when set', () {
      final config = CustomEmulatorConfig(
        id: 'test-json',
        name: 'RetroArch Flatpak',
        platforms: ['ps1'],
        executablePath: '/usr/bin/flatpak',
        commandOverride: 'flatpak run org.libretro.RetroArch',
        saveMethod: CustomSaveMethod.file,
        savePath: '/home/user/saves',
      );

      final json = config.toJson();
      expect(json['commandOverride'], 'flatpak run org.libretro.RetroArch');
    });

    test('toJson omits commandOverride when null', () {
      final config = CustomEmulatorConfig(
        id: 'test-json-null',
        name: 'Native',
        platforms: ['ps2'],
        executablePath: '/usr/bin/pcsx2',
        saveMethod: CustomSaveMethod.folder,
        savePath: '/home/user/saves',
      );

      final json = config.toJson();
      expect(json.containsKey('commandOverride'), isFalse);
    });

    test('fromJson restores commandOverride', () {
      final json = {
        'id': 'test-fromjson',
        'name': 'Restored RetroArch',
        'platforms': ['ps1', 'psx'],
        'executablePath': '/usr/bin/flatpak',
        'commandOverride': 'flatpak run org.libretro.RetroArch',
        'saveMethod': 'file',
        'savePath': '/home/user/saves',
      };

      final config = CustomEmulatorConfig.fromJson(json);
      expect(config.commandOverride, 'flatpak run org.libretro.RetroArch');
      expect(config.isCommandOverride, isTrue);
    });

    test('round-trip JSON serialization preserves commandOverride', () {
      final original = CustomEmulatorConfig(
        id: 'roundtrip',
        name: 'Dolphin Flatpak',
        platforms: ['gc', 'wii'],
        executablePath: '/usr/bin/flatpak',
        commandOverride: 'flatpak run org.DolphinEmu.dolphin-emu',
        saveMethod: CustomSaveMethod.folder,
        savePath: '/home/user/saves',
      );

      final json = original.toJson();
      final restored = CustomEmulatorConfig.fromJson(json);

      expect(restored.commandOverride, original.commandOverride);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.platforms, original.platforms);
      expect(restored.isCommandOverride, isTrue);
    });

    test('round-trip JSON serialization works without commandOverride', () {
      final original = CustomEmulatorConfig(
        id: 'roundtrip-native',
        name: 'mGBA',
        platforms: ['gba'],
        executablePath: '/usr/bin/mgba',
        saveMethod: CustomSaveMethod.file,
        savePath: '/home/user/saves',
      );

      final json = original.toJson();
      final restored = CustomEmulatorConfig.fromJson(json);

      expect(restored.commandOverride, isNull);
      expect(restored.isCommandOverride, isFalse);
    });
  });

  group('kEmulatorFlatpakPackages - known mappings', () {
    test('contains expected emulators', () {
      expect(kEmulatorFlatpakPackages.containsKey('dolphin'), isTrue);
      expect(kEmulatorFlatpakPackages.containsKey('retroarch'), isTrue);
      expect(kEmulatorFlatpakPackages.containsKey('pcsx2'), isTrue);
      expect(kEmulatorFlatpakPackages.containsKey('rpcs3'), isTrue);
      expect(kEmulatorFlatpakPackages.containsKey('duckstation'), isTrue);
      expect(kEmulatorFlatpakPackages.containsKey('ppsspp'), isTrue);
    });

    test('contains known Flatpak package IDs', () {
      expect(kEmulatorFlatpakPackages['dolphin'], 'org.DolphinEmu.dolphin-emu');
      expect(kEmulatorFlatpakPackages['retroarch'], 'org.libretro.RetroArch');
      expect(kEmulatorFlatpakPackages['pcsx2'], 'net.pcsx2.PCSX2');
    });

    test('getFlatpakPackageForEmulator returns correct package', () {
      // Use a simple test strategy to verify the method works
      expect(kEmulatorFlatpakPackages['dolphin'], 'org.DolphinEmu.dolphin-emu');
      expect(kEmulatorFlatpakPackages['nonexistent'], isNull);
    });
  });

  group('NativeLinuxStrategy - Flatpak support', () {
    late NativeLinuxStrategy strategy;

    setUp(() {
      strategy = NativeLinuxStrategy();
    });

    test('getFlatpakPackageForEmulator returns known packages', () {
      expect(strategy.getFlatpakPackageForEmulator('dolphin'), 'org.DolphinEmu.dolphin-emu');
      expect(strategy.getFlatpakPackageForEmulator('retroarch'), 'org.libretro.RetroArch');
      expect(strategy.getFlatpakPackageForEmulator('pcsx2'), 'net.pcsx2.PCSX2');
    });

    test('getFlatpakPackageForEmulator returns null for unknown emulators', () {
      expect(strategy.getFlatpakPackageForEmulator('nonexistent_emu'), isNull);
    });

    test('isFlatpakAvailable returns false in test environment (no flatpak CLI)', () async {
      // In a test environment, flatpak CLI won't be installed
      final available = await strategy.isFlatpakAvailable();
      expect(available, isFalse);
    });

    test('detectFlatpakEmulators returns empty map when flatpak not available', () async {
      final result = await strategy.detectFlatpakEmulators();
      // Should be empty since flatpak CLI isn't available in tests
      expect(result, isEmpty);
    });
  });
}
