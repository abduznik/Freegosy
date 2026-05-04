import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/emulator/linux_strategies/emudeck_strategy.dart';
import 'package:freegosy/core/emulator/linux_strategies/retrodeck_strategy.dart';

void main() {
  group('Linux Environment Strategies Path Resolution', () {
    late Directory tempHome;
    late Directory emudeckRoot;
    late Directory retrodeckVarConfig;
    
    late EmuDeckStrategy emudeckStrategy;
    late RetroDeckStrategy retrodeckStrategy;

    setUp(() async {
      // Create a fake home directory
      tempHome = await Directory.systemTemp.createTemp('freegosy_test_home_');
      
      // --- Setup Mock EmuDeck Structure ---
      // EmuDeck normally lives in ~/Emulation or an SD card
      emudeckRoot = Directory(p.join(tempHome.path, 'Emulation'));
      await emudeckRoot.create();
      
      await Directory(p.join(emudeckRoot.path, 'roms')).create();
      await Directory(p.join(emudeckRoot.path, 'tools', 'launchers')).create(recursive: true);
      await Directory(p.join(emudeckRoot.path, 'bios')).create();
      
      // Mock EmuDeck Save symlink structure for Cemu
      final cemuSaves = Directory(p.join(emudeckRoot.path, 'saves', 'Cemu', 'saves'));
      await cemuSaves.create(recursive: true);

      // Create a dummy launch script
      final launcher = File(p.join(emudeckRoot.path, 'tools', 'launchers', 'cemu.sh'));
      await launcher.writeAsString('#!/bin/bash');

      // --- Setup Mock RetroDECK Structure ---
      await Directory(p.join(tempHome.path, 'retrodeck', 'roms')).create(recursive: true);
      await Directory(p.join(tempHome.path, 'retrodeck', 'tools')).create(recursive: true);
      
      // RetroDECK uses Flatpak standard paths
      retrodeckVarConfig = Directory(p.join(tempHome.path, '.var', 'app', 'net.retrodeck.retrodeck', 'config'));
      await Directory(p.join(retrodeckVarConfig.path, 'bios')).create(recursive: true);
      
      // Mock RetroDECK save structure for PCSX2
      await Directory(p.join(retrodeckVarConfig.path, 'PCSX2', 'saves')).create(recursive: true);

      // Initialize strategies
      emudeckStrategy = EmuDeckStrategy();
      retrodeckStrategy = RetroDeckStrategy();
    });

    tearDown(() async {
      // Clean up the fake file tree
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    group('EmuDeckStrategy', () {
      test('Resolves ROMs root correctly', () {
        // EmuDeck Strategy checks for Emulation/roms
        final result = emudeckStrategy.getRomsRoot(tempHome.path, null, tempHome.path);
        expect(result, p.join(tempHome.path, 'Emulation', 'roms'));
      });

      test('Resolves Tools root correctly', () {
        // EmuDeck Strategy checks for Emulation/tools
        final result = emudeckStrategy.getEmulatorsRoot(tempHome.path, null, tempHome.path);
        expect(result, p.join(tempHome.path, 'Emulation', 'tools'));
      });

      test('Resolves specific save symlink directory correctly', () {
        // We mocked 'Cemu' and its 'saves' subfolder, which EmuDeckStrategy should prioritize
        final result = emudeckStrategy.getEmulatorAppSupportDirectory(tempHome.path, 'cemu', tempHome.path);
        expect(result, p.join(tempHome.path, 'Emulation', 'saves', 'Cemu', 'saves'));
      });

      test('Finds EmuDeck specific launcher script', () async {
        // EmuDeck map maps 'cemu' to 'cemu.sh'
        final result = await emudeckStrategy.findExecutable('cemu', 'Cemu.AppImage', tempHome.path, tempHome.path);
        expect(result, p.join(tempHome.path, 'Emulation', 'tools', 'launchers', 'cemu.sh'));
      });
    });

    group('RetroDeckStrategy', () {
      test('Resolves ROMs root correctly', () {
        // RetroDECK ROMs are in ~/retrodeck/roms
        final result = retrodeckStrategy.getRomsRoot(tempHome.path, null, null);
        expect(result, p.join(tempHome.path, 'retrodeck', 'roms'));
      });

      test('Resolves Flatpak BIOS directory correctly', () {
        // RetroDECK bios are in ~/.var/app/net.retrodeck.retrodeck/config/bios
        final result = retrodeckStrategy.getBiosPath(tempHome.path, null);
        expect(result, p.join(tempHome.path, '.var', 'app', 'net.retrodeck.retrodeck', 'config', 'bios'));
      });

      test('Resolves Flatpak Save directory correctly', () {
        // We mocked PCSX2 with a 'saves' subfolder inside the flatpak config
        final result = retrodeckStrategy.getEmulatorAppSupportDirectory(tempHome.path, 'pcsx2', null);
        expect(result, p.join(retrodeckVarConfig.path, 'PCSX2', 'saves'));
      });
    });
  });
}
